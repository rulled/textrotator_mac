import Foundation
import AppKit
import SwiftUI

@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    public static var shared: StatusBarController?
    private var statusItem: NSStatusItem?
    private var cursorTranslateItem: NSMenuItem?
    private let coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        StatusBarController.shared = self
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
        menu.autoenablesItems = false

        // 1. Open Window / Manager
        let managerItem = NSMenuItem(
            title: "Показать окно менеджера...",
            action: #selector(openManagerWindow),
            keyEquivalent: ","
        )
        managerItem.target = self
        managerItem.isEnabled = true
        menu.addItem(managerItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Cursor Translate Toggle
        let hotkey = coordinator.currentKeyCombo(for: .cursorTranslateToggle).displayString
        let cursorItem = NSMenuItem(
            title: "Автоперевод при выделении (\(hotkey))",
            action: #selector(toggleCursorTranslate),
            keyEquivalent: ""
        )
        cursorItem.target = self
        cursorItem.state = coordinator.isCursorTranslateEnabled ? .on : .off
        cursorItem.isEnabled = true
        menu.addItem(cursorItem)
        self.cursorTranslateItem = cursorItem

        menu.addItem(NSMenuItem.separator())

        // 3. Check for Updates
        let updateItem = NSMenuItem(
            title: "Проверить обновления...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.isEnabled = true
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Quit
        let quitItem = NSMenuItem(
            title: "Завершить программу",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        // Update item states directly without replacing statusItem.menu mid-flight
        let hotkey = coordinator.currentKeyCombo(for: .cursorTranslateToggle).displayString
        cursorTranslateItem?.title = "Автоперевод при выделении (\(hotkey))"
        cursorTranslateItem?.state = coordinator.isCursorTranslateEnabled ? .on : .off
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }

    @objc private func openManagerWindow() {
        WindowManager.shared.openManagerWindow(coordinator: coordinator)
    }

    @objc private func toggleCursorTranslate() {
        coordinator.toggleCursorTranslateMode()
        buildMenu()
    }

    @objc private func checkForUpdates() {
        UpdateService.shared.checkForUpdates(isUserInitiated: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
