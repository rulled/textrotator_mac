import Foundation
import AppKit
import TextRotatorCore

/// Monitors global mouse gestures to detect text selection release (drag-select or double/triple click).
@MainActor
public final class CursorSelectionWatcher {
    private var globalMonitor: Any?
    private var mouseDownLocation: NSPoint?
    private var isDragging: Bool = false
    private let onSelectionReleased: (String) -> Void
    private let textIO: TextIOServiceProtocol

    public private(set) var isRunning: Bool = false

    public init(textIO: TextIOServiceProtocol = TextIOService.shared, onSelectionReleased: @escaping (String) -> Void) {
        self.textIO = textIO
        self.onSelectionReleased = onSelectionReleased
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                self.handleMouseEvent(event)
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        mouseDownLocation = nil
        isDragging = false
    }

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownLocation = NSEvent.mouseLocation
            isDragging = false

        case .leftMouseDragged:
            if let start = mouseDownLocation {
                let current = NSEvent.mouseLocation
                let distance = hypot(current.x - start.x, current.y - start.y)
                if distance > 14 {
                    isDragging = true
                }
            }

        case .leftMouseUp:
            let wasDragging = isDragging
            let isMultiClick = event.clickCount >= 2
            mouseDownLocation = nil
            isDragging = false

            if wasDragging || isMultiClick {
                // Brief debounce delay to allow target application to update AXSelectedText
                Task {
                    try? await Task.sleep(nanoseconds: 70_000_000) // 70ms
                    guard self.isRunning else { return }

                    // Ignore if frontmost app is TextRotator itself
                    if let frontApp = NSWorkspace.shared.frontmostApplication,
                       frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
                        return
                    }

                    if let selected = await self.textIO.captureSelectedText() {
                        let cleaned = selected.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Trigger only on meaningful selection (at least 2 non-whitespace characters)
                        if cleaned.count >= 2 {
                            self.onSelectionReleased(cleaned)
                        }
                    }
                }
            }

        default:
            break
        }
    }
}
