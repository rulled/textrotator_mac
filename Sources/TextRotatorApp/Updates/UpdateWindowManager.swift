import Foundation
import AppKit
import SwiftUI

@MainActor
public final class UpdateWindowManager: NSObject, NSWindowDelegate {
    public static let shared = UpdateWindowManager()
    private var window: NSWindow?

    public func presentUpdateModal(info: UpdateInfo) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = true
        newWindow.level = .floating
        newWindow.isMovableByWindowBackground = true
        newWindow.delegate = self
        newWindow.center()

        let rootView = UpdateModalView(info: info)
        newWindow.contentView = NSHostingView(rootView: rootView)

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closeModal() {
        window?.orderOut(nil)
        window = nil
    }

    public func presentUpToDateToast(version: String) {
        let alert = NSAlert()
        alert.messageText = "Установлена актуальная версия"
        alert.informativeText = "TextRotator v\(version) является самой свежей версией."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    public func presentErrorAlert(error: String) {
        let alert = NSAlert()
        alert.messageText = "Не удалось проверить обновления"
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Понятно")
        alert.runModal()
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
