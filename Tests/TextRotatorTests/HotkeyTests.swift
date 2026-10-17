import XCTest
@testable import TextRotatorCore

private final class TestCounter: @unchecked Sendable {
    private var value: Int = 0
    private let lock = NSLock()

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
final class HotkeyTests: XCTestCase {


    // MARK: - HotkeyAction & KeyCombo Tests

    func testHotkeyActionProperties() {
        let actions = HotkeyAction.allCases
        XCTAssertEqual(actions.count, 4)

        XCTAssertEqual(HotkeyAction.instantTranslateAndReplace.defaultKeyString, "F1")
        XCTAssertEqual(HotkeyAction.cursorTranslateToggle.defaultKeyString, "F2")
        XCTAssertEqual(HotkeyAction.quickSnippetsOverlay.defaultKeyString, "F3")
        XCTAssertEqual(HotkeyAction.translatorOverlay.defaultKeyString, "F4")

        XCTAssertEqual(HotkeyAction.instantTranslateAndReplace.rawId, 1)
        XCTAssertEqual(HotkeyAction.cursorTranslateToggle.rawId, 2)
        XCTAssertEqual(HotkeyAction.quickSnippetsOverlay.rawId, 3)
        XCTAssertEqual(HotkeyAction.translatorOverlay.rawId, 4)

        for action in actions {
            XCTAssertEqual(HotkeyAction(rawId: action.rawId), action)
            XCTAssertFalse(action.displayName.isEmpty)
        }
    }

    func testKeyComboParsingAndDisplay() {
        let f1 = KeyCombo(string: "F1")
        XCTAssertNotNil(f1)
        XCTAssertEqual(f1?.keyCode, KeyCode.f1)
        XCTAssertEqual(f1?.modifiers, [])
        XCTAssertEqual(f1?.displayString, "F1")

        let cmdShiftV = KeyCombo(string: "Cmd+Shift+V")
        XCTAssertNotNil(cmdShiftV)
        XCTAssertEqual(cmdShiftV?.keyCode, KeyCode.v)
        XCTAssertTrue(cmdShiftV?.modifiers.contains(.command) == true)
        XCTAssertTrue(cmdShiftV?.modifiers.contains(.shift) == true)
        XCTAssertFalse(cmdShiftV?.modifiers.contains(.option) == true)

        let optSpace = KeyCombo(string: "Option+Space")
        XCTAssertNotNil(optSpace)
        XCTAssertEqual(optSpace?.keyCode, KeyCode.space)
        XCTAssertEqual(optSpace?.modifiers, .option)
        XCTAssertEqual(optSpace?.displayString, "⌥Space")

        let symbolsCombo = KeyCombo(string: "⌘⇧V")
        XCTAssertNotNil(symbolsCombo)
        XCTAssertEqual(symbolsCombo?.keyCode, KeyCode.v)
        XCTAssertTrue(symbolsCombo?.modifiers.contains(.command) == true)
        XCTAssertTrue(symbolsCombo?.modifiers.contains(.shift) == true)
    }

    func testKeyModifiersCarbonModifiers() {
        let allMods: KeyModifiers = [.command, .shift, .option, .control]
        let carbon = allMods.carbonModifiers

        XCTAssertNotEqual(carbon & 0x0100, 0) // cmdKey
        XCTAssertNotEqual(carbon & 0x0200, 0) // shiftKey
        XCTAssertNotEqual(carbon & 0x0800, 0) // optionKey
        XCTAssertNotEqual(carbon & 0x1000, 0) // controlKey

        let reconstructed = KeyModifiers.fromCarbonModifiers(carbon)
        XCTAssertEqual(reconstructed, allMods)
    }

    func testHotkeyConfigurationDefaults() {
        let config = HotkeyConfiguration.default

        let instant = config.keyCombo(for: .instantTranslateAndReplace)
        XCTAssertEqual(instant?.keyCode, KeyCode.f1)

        let cursor = config.keyCombo(for: .cursorTranslateToggle)
        XCTAssertEqual(cursor?.keyCode, KeyCode.f2)

        let rotation = config.keyCombo(for: .quickSnippetsOverlay)
        XCTAssertEqual(rotation?.keyCode, KeyCode.f3)

        let translation = config.keyCombo(for: .translatorOverlay)
        XCTAssertEqual(translation?.keyCode, KeyCode.f4)
    }

    // MARK: - ActionPipeline Concurrency & Debounce Tests

    func testPipelineDispatchExecutesOnWorkerQueue() {
        let pipeline = ActionPipeline(debounceInterval: 0.180)
        let expectation = expectation(description: "Handler invoked")

        pipeline.subscribe { action in
            XCTAssertEqual(action, .quickSnippetsOverlay)
            expectation.fulfill()
        }

        let accepted = pipeline.dispatch(.quickSnippetsOverlay)
        XCTAssertTrue(accepted)

        wait(for: [expectation], timeout: 2.0)
    }

    func testDebounceDropsRapidConsecutiveDispatches() {
        let pipeline = ActionPipeline(debounceInterval: 0.180, autoResetOperationInProgress: true)
        let expectation = expectation(description: "First dispatch handled")
        let counter = TestCounter()

        pipeline.subscribe { _ in
            _ = counter.increment()
            expectation.fulfill()
        }

        // First dispatch should succeed
        let accepted1 = pipeline.dispatch(.instantTranslateAndReplace)
        XCTAssertTrue(accepted1)

        // Rapid subsequent dispatches within 180 ms should be dropped
        let accepted2 = pipeline.dispatch(.instantTranslateAndReplace)
        XCTAssertFalse(accepted2, "Second consecutive dispatch within 180ms must be rejected")

        let accepted3 = pipeline.dispatch(.instantTranslateAndReplace)
        XCTAssertFalse(accepted3, "Third consecutive dispatch within 180ms must be rejected")

        wait(for: [expectation], timeout: 2.0)

        // Give any extra potential errant worker queue runs a moment
        Thread.sleep(forTimeInterval: 0.05)

        XCTAssertEqual(counter.current, 1, "Handler should only have been called once")
    }

    func testDebounceAllowsDispatchAfterInterval() async throws {
        let pipeline = ActionPipeline(debounceInterval: 0.100, autoResetOperationInProgress: true)

        let exp1 = expectation(description: "First dispatch")
        let exp2 = expectation(description: "Second dispatch after interval")

        let counter = TestCounter()

        pipeline.subscribe { _ in
            let val = counter.increment()
            if val == 1 {
                exp1.fulfill()
            } else if val == 2 {
                exp2.fulfill()
            }
        }

        let first = pipeline.dispatch(.translatorOverlay)
        XCTAssertTrue(first)
        await fulfillment(of: [exp1], timeout: 1.0)

        // Wait longer than debounceInterval
        try await Task.sleep(nanoseconds: 120_000_000) // 120 ms > 100 ms

        let second = pipeline.dispatch(.translatorOverlay)
        XCTAssertTrue(second, "Dispatch after debounce interval must be accepted")
        await fulfillment(of: [exp2], timeout: 1.0)

        XCTAssertEqual(counter.current, 2)
    }

    func testDebounceIsPerActionType() {
        let pipeline = ActionPipeline(debounceInterval: 0.180, autoResetOperationInProgress: true)

        let exp1 = expectation(description: "First action")
        let exp2 = expectation(description: "Second distinct action")

        pipeline.subscribe { action in
            if action == .quickSnippetsOverlay {
                exp1.fulfill()
            } else if action == .cursorTranslateToggle {
                exp2.fulfill()
            }
        }

        // Dispatch Action A
        let firstAccepted = pipeline.dispatch(.quickSnippetsOverlay)
        XCTAssertTrue(firstAccepted)

        // Ensure operation flag is released by worker
        wait(for: [exp1], timeout: 1.0)
        pipeline.setOperationInProgress(false)

        // Dispatch Action B (different action type) immediately -> should be accepted!
        let secondAccepted = pipeline.dispatch(.cursorTranslateToggle)
        XCTAssertTrue(secondAccepted, "Different action type should have its own debounce timer")

        // Dispatch Action B again immediately -> should be debounced!
        let thirdAccepted = pipeline.dispatch(.cursorTranslateToggle)
        XCTAssertFalse(thirdAccepted, "Identical action within debounce interval must be rejected")

        wait(for: [exp2], timeout: 1.0)
    }

    func testConcurrencyLockPreventsReentrantExecution() {
        let pipeline = ActionPipeline(debounceInterval: 0.180, autoResetOperationInProgress: false)

        // Manually acquire lock (simulating capture in progress)
        pipeline.setOperationInProgress(true)
        XCTAssertTrue(pipeline.isOperationInProgress)

        // Attempts to dispatch any action should be rejected
        let rejected1 = pipeline.dispatch(.quickSnippetsOverlay)
        XCTAssertFalse(rejected1, "Dispatch must be rejected while isOperationInProgress is true")

        let rejected2 = pipeline.dispatch(.instantTranslateAndReplace)
        XCTAssertFalse(rejected2, "Dispatch of any action must be rejected while isOperationInProgress is true")

        // Release lock
        pipeline.setOperationInProgress(false)
        XCTAssertFalse(pipeline.isOperationInProgress)

        // Now dispatch should be accepted
        let accepted = pipeline.dispatch(.translatorOverlay)
        XCTAssertTrue(accepted, "Dispatch should be accepted after isOperationInProgress is cleared")
    }

    func testAsyncHandlerConcurrencyLocking() async throws {
        let pipeline = ActionPipeline(debounceInterval: 0.050, autoResetOperationInProgress: true)

        let firstStarted = expectation(description: "First operation started")
        let firstFinished = expectation(description: "First operation finished")

        pipeline.setAsyncHandler { action in
            if action == .instantTranslateAndReplace {
                firstStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                firstFinished.fulfill()
            }
        }

        let firstDispatched = pipeline.dispatch(.instantTranslateAndReplace)
        XCTAssertTrue(firstDispatched)

        await fulfillment(of: [firstStarted], timeout: 1.0)

        // While first operation is in flight, isOperationInProgress MUST be true
        XCTAssertTrue(pipeline.isOperationInProgress, "isOperationInProgress should remain true while async handler runs")

        // Any second action while in progress must be rejected
        let secondDispatched = pipeline.dispatch(.cursorTranslateToggle)
        XCTAssertFalse(secondDispatched, "Concurrent action must be rejected while operation is in progress")

        await fulfillment(of: [firstFinished], timeout: 2.0)

        // Wait a brief moment for autoReset to set isOperationInProgress = false
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(pipeline.isOperationInProgress, "isOperationInProgress should reset after async handler finishes")
    }

    func testMultipleSubscribersAndUnsubscribe() {
        let pipeline = ActionPipeline(debounceInterval: 0.010, autoResetOperationInProgress: true)

        let counter1 = TestCounter()
        let counter2 = TestCounter()

        let exp1 = expectation(description: "First dispatch sub 1")
        let exp2 = expectation(description: "First dispatch sub 2")

        let id1 = pipeline.subscribe { _ in
            _ = counter1.increment()
            exp1.fulfill()
        }
        let id2 = pipeline.subscribe { _ in
            _ = counter2.increment()
            exp2.fulfill()
        }

        _ = pipeline.dispatch(.quickSnippetsOverlay)
        wait(for: [exp1, exp2], timeout: 1.0)
        XCTAssertEqual(counter1.current, 1)
        XCTAssertEqual(counter2.current, 1)

        // Unsubscribe sub 1 and sub 2
        pipeline.unsubscribe(id1)
        pipeline.unsubscribe(id2)
        pipeline.resetDebounce()

        let exp3 = expectation(description: "Second dispatch new sub")
        _ = pipeline.subscribe { _ in
            _ = counter2.increment()
            exp3.fulfill()
        }

        _ = pipeline.dispatch(.quickSnippetsOverlay)
        wait(for: [exp3], timeout: 1.0)

        XCTAssertEqual(counter1.current, 1, "Sub 1 should NOT be called after unsubscribe")
        XCTAssertEqual(counter2.current, 2, "New subscriber should have been called")
    }

    // MARK: - HotkeyService Integration Tests

    func testHotkeyServiceTriggerDirect() {
        let service = HotkeyService()
        let exp = expectation(description: "Service trigger dispatches to pipeline")

        service.pipeline.subscribe { action in
            XCTAssertEqual(action, .quickSnippetsOverlay)
            exp.fulfill()
        }

        let triggered = service.trigger(.quickSnippetsOverlay)
        XCTAssertTrue(triggered)

        wait(for: [exp], timeout: 1.0)
    }

    func testHotkeyServiceRegisterAndUnregister() throws {
        let service = HotkeyService()

        let customCombo = KeyCombo(keyCode: KeyCode.k, modifiers: [.command, .shift])
        try service.register(action: .quickSnippetsOverlay, combo: customCombo)

        XCTAssertEqual(service.configuration.keyCombo(for: .quickSnippetsOverlay), customCombo)

        service.unregister(action: .quickSnippetsOverlay)
        XCTAssertNil(service.configuration.keyCombo(for: .quickSnippetsOverlay))
    }
}
