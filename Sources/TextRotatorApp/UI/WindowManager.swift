import Foundation
import AppKit
import SwiftUI

@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()

    private var managerWindow: NSWindow?

    public func openManagerWindow(coordinator: AppCoordinator) {
        if let existing = managerWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 850, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Text Rotator"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 650, height: 420)
        window.delegate = self
        window.isReleasedWhenClosed = false

        let contentView = SnippetsManagerView(coordinator: coordinator)
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        self.managerWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        managerWindow = nil
    }
}
