import Foundation
import AppKit
import SwiftUI

@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "TextRotator") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "TR"
            }
        }

        buildMenu()
    }

    public func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // 1. Open Window / Manager
        let managerItem = NSMenuItem(
            title: "Показать окно менеджера...",
            action: #selector(openManagerWindow),
            keyEquivalent: ","
        )
        managerItem.target = self
        menu.addItem(managerItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Cursor Translate Toggle
        let cursorTranslateItem = NSMenuItem(
            title: "Автоперевод при выделении (F2)",
            action: #selector(toggleCursorTranslate),
            keyEquivalent: ""
        )
        cursorTranslateItem.target = self
        cursorTranslateItem.state = coordinator.isCursorTranslateEnabled ? .on : .off
        menu.addItem(cursorTranslateItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Quit
        let quitItem = NSMenuItem(
            title: "Завершить программу",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        // Refresh checkmark state when user clicks the menu item
        buildMenu()
    }

    @objc private func openManagerWindow() {
        WindowManager.shared.openManagerWindow(coordinator: coordinator)
    }

    @objc private func toggleCursorTranslate() {
        coordinator.toggleCursorTranslateMode()
        buildMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
