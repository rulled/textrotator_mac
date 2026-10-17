import XCTest
import AppKit
import ApplicationServices
import Carbon
@testable import TextRotatorCore

// MARK: - Mocks

final class MockAccessibilityDriver: TextAccessibilityDriver, @unchecked Sendable {
    var isProcessTrustedResult: Bool = true
    var promptAccessibilityCalled: Bool = false
    var selectedTextToReturn: String? = nil
    var setSelectedTextResult: Bool = true
    var lastSetText: String? = nil
    var copySelectedTextCallCount: Int = 0
    var setSelectedTextCallCount: Int = 0

    func isProcessTrusted() -> Bool {
        return isProcessTrustedResult
    }

    func promptAccessibility() {
        promptAccessibilityCalled = true
    }

    func copySelectedText() -> String? {
        copySelectedTextCallCount += 1
        return selectedTextToReturn
    }

    func setSelectedText(_ text: String) -> Bool {
        setSelectedTextCallCount += 1
        lastSetText = text
        return setSelectedTextResult
    }
}

final class MockPasteboardDriver: TextPasteboardDriver, @unchecked Sendable {
    var storage: [NSPasteboard.PasteboardType: String] = [:]
    var currentChangeCount: Int = 1
    var clearContentsCallCount: Int = 0
    var writtenTypes: [NSPasteboard.PasteboardType] = []

    func clearContents() -> Int {
        clearContentsCallCount += 1
        storage.removeAll()
        writtenTypes.removeAll()
        currentChangeCount += 1
        return currentChangeCount
    }

    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        storage[type] = string
        writtenTypes.append(type)
        return true
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        return storage[type]
    }

    func changeCount() -> Int {
        return currentChangeCount
    }

    func simulateExternalCopy(text: String) {
        currentChangeCount += 1
        storage[.string] = text
    }
}

final class MockKeyEventSimulatorDriver: KeyEventSimulatorDriver, @unchecked Sendable {
    var simulateKeyResult: Bool = true
    var simulatedKeys: [(keyCode: CGKeyCode, flags: CGEventFlags)] = []
    var onKeySimulated: ((CGKeyCode, CGEventFlags) -> Void)?

    func simulateKey(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        simulatedKeys.append((keyCode, flags))
        onKeySimulated?(keyCode, flags)
        return simulateKeyResult
    }
}

final class MockAppActivationDriver: AppActivationDriver, @unchecked Sendable {
    var activateFrontmostAppCallCount: Int = 0

    func activateFrontmostAppIfNeeded() {
        activateFrontmostAppCallCount += 1
    }
}

// MARK: - Unit Tests

final class TextIOTests: XCTestCase {
    private var mockAccessibility: MockAccessibilityDriver!
    private var mockPasteboard: MockPasteboardDriver!
    private var mockKeySimulator: MockKeyEventSimulatorDriver!
    private var mockActivation: MockAppActivationDriver!
    private var service: TextIOService!

    override func setUp() {
        super.setUp()
        mockAccessibility = MockAccessibilityDriver()
        mockPasteboard = MockPasteboardDriver()
        mockKeySimulator = MockKeyEventSimulatorDriver()
        mockActivation = MockAppActivationDriver()
        service = TextIOService(
            accessibilityDriver: mockAccessibility,
            pasteboardDriver: mockPasteboard,
            keyEventSimulator: mockKeySimulator,
            appActivationDriver: mockActivation
        )
    }

    override func tearDown() {
        mockAccessibility = nil
        mockPasteboard = nil
        mockKeySimulator = nil
        mockActivation = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Accessibility Permissions

    func testAccessibilityGranted_whenTrue_returnsTrue() {
        mockAccessibility.isProcessTrustedResult = true
        XCTAssertTrue(service.isAccessibilityGranted())
    }

    func testAccessibilityGranted_whenFalse_returnsFalse() {
        mockAccessibility.isProcessTrustedResult = false
        XCTAssertFalse(service.isAccessibilityGranted())
    }

    func testPromptAccessibilityPermission_delegatesToDriver() {
        XCTAssertFalse(mockAccessibility.promptAccessibilityCalled)
        service.promptAccessibilityPermission()
        XCTAssertTrue(mockAccessibility.promptAccessibilityCalled)
    }

    // MARK: - Text Capture (Method 1 & Method 2)

    func testCaptureSelectedText_method1_AXSuccess_returnsDirectTextWithoutPasteboard() async {
        mockAccessibility.selectedTextToReturn = "Direct Selection via AX"

        let captured = await service.captureSelectedText()

        XCTAssertEqual(captured, "Direct Selection via AX")
        XCTAssertEqual(mockAccessibility.copySelectedTextCallCount, 1)
        XCTAssertEqual(mockKeySimulator.simulatedKeys.count, 0)
        XCTAssertEqual(mockPasteboard.clearContentsCallCount, 0)
    }

    func testCaptureSelectedText_method1_AXFails_fallbackToMethod2_CmdCSuccess() async {
        mockAccessibility.selectedTextToReturn = nil

        // When Cmd+C (key code 0x08) is simulated, simulate target app writing to clipboard
        mockKeySimulator.onKeySimulated = { [weak self] keyCode, flags in
            guard let self = self else { return }
            if keyCode == 0x08 && flags.contains(.maskCommand) {
                self.mockPasteboard.simulateExternalCopy(text: "Captured via Cmd+C fallback")
            }
        }

        let captured = await service.captureSelectedText()

        XCTAssertEqual(captured, "Captured via Cmd+C fallback")
        XCTAssertEqual(mockAccessibility.copySelectedTextCallCount, 1)
        XCTAssertEqual(mockKeySimulator.simulatedKeys.count, 1)
        XCTAssertEqual(mockKeySimulator.simulatedKeys[0].keyCode, 0x08)
        XCTAssertTrue(mockKeySimulator.simulatedKeys[0].flags.contains(.maskCommand))
    }

    func testCaptureSelectedText_method2_keySimulationFails_returnsNil() async {
        mockAccessibility.selectedTextToReturn = nil
        mockKeySimulator.simulateKeyResult = false

        let captured = await service.captureSelectedText()

        XCTAssertNil(captured)
        XCTAssertEqual(mockAccessibility.copySelectedTextCallCount, 1)
        XCTAssertEqual(mockKeySimulator.simulatedKeys.count, 1)
    }

    func testCaptureSelectedText_method2_timeoutWithoutChangeCountUpdate_returnsNil() async {
        mockAccessibility.selectedTextToReturn = nil
        // Do not update pasteboard changeCount; simulates no text selected

        let captured = await service.captureSelectedText()

        XCTAssertNil(captured)
        XCTAssertEqual(mockAccessibility.copySelectedTextCallCount, 1)
        XCTAssertEqual(mockKeySimulator.simulatedKeys.count, 1)
    }

    // MARK: - Text Insertion (Level 1 & Level 2)

    func testInsertText_level1_AXSuccess_replacesInPlaceWithoutPasteboard() async throws {
        mockAccessibility.setSelectedTextResult = true

        try await service.insertText("Direct replacement text")

        XCTAssertEqual(mockAccessibility.setSelectedTextCallCount, 1)
        XCTAssertEqual(mockAccessibility.lastSetText, "Direct replacement text")
        XCTAssertEqual(mockPasteboard.clearContentsCallCount, 0)
        XCTAssertEqual(mockKeySimulator.simulatedKeys.count, 0)
        XCTAssertEqual(mockActivation.activateFrontmostAppCallCount, 0)
    }

    func testInsertText_level1_AXFails_level2_fallbackToConcealedPasteboardAndCmdV() async throws {
        mockAccessibility.setSelectedTextResult = false

        try await service.insertText("Concealed paste text")

        // 1. Accessibility was attempted
        XCTAssertEqual(mockAccessibility.setSelectedTextCallCount, 1)
        XCTAssertEqual(mockAccessibility.lastSetText, "Concealed paste text")

        // 2. Frontmost app activation was requested
        XCTAssertEqual(mockActivation.activateFrontmostAppCallCount, 1)

        // 3. Pasteboard was cleared and populated with text
        XCTAssertEqual(mockPasteboard.clearContentsCallCount, 1)
        XCTAssertEqual(mockPasteboard.string(forType: .string), "Concealed paste text")

        // 4. Concealment metadata types were written to avoid clipboard manager pollution
        XCTAssertTrue(mockPasteboard.writtenTypes.contains(.transient))
        XCTAssertTrue(mockPasteboard.writtenTypes.contains(.autoGenerated))
        XCTAssertTrue(mockPasteboard.writtenTypes.contains(.concealed))

        // 5. Cmd+V (0x09) simulation was triggered
        XCTAssertEqual(mockKeySimulator.simulatedKeys.count, 1)
        XCTAssertEqual(mockKeySimulator.simulatedKeys[0].keyCode, 0x09)
        XCTAssertTrue(mockKeySimulator.simulatedKeys[0].flags.contains(.maskCommand))
    }

    func testInsertText_level2_eventSimulationFails_throwsEventSimulationFailed() async {
        mockAccessibility.setSelectedTextResult = false
        mockKeySimulator.simulateKeyResult = false

        do {
            try await service.insertText("Failed simulation text")
            XCTFail("Expected eventSimulationFailed error to be thrown")
        } catch let error as TextIOError {
            XCTAssertEqual(error, TextIOError.eventSimulationFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Pasteboard Concealment Constants & Errors

    func testPasteboardConcealmentTypeConstants() {
        XCTAssertEqual(NSPasteboard.PasteboardType.transient.rawValue, "org.nspasteboard.TransientType")
        XCTAssertEqual(NSPasteboard.PasteboardType.autoGenerated.rawValue, "org.nspasteboard.AutoGeneratedType")
        XCTAssertEqual(NSPasteboard.PasteboardType.concealed.rawValue, "org.nspasteboard.ConcealedType")
    }

    func testTextIOErrorDescriptions() {
        let simError = TextIOError.eventSimulationFailed
        XCTAssertNotNil(simError.errorDescription)
        XCTAssertTrue(simError.errorDescription!.contains("simulate keyboard event"))

        let insertError = TextIOError.insertionFailed("Blocked")
        XCTAssertNotNil(insertError.errorDescription)
        XCTAssertTrue(insertError.errorDescription!.contains("Blocked"))

        let accessError = TextIOError.accessibilityUnavailable
        XCTAssertNotNil(accessError.errorDescription)
        XCTAssertTrue(accessError.errorDescription!.contains("Accessibility permissions"))
    }
}
