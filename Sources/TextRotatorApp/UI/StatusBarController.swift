import Foundation
import AppKit
import SwiftUI

@MainActor
public final class StatusBarController: NSObject {
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

        // 1. Actions
        let snippetsItem = NSMenuItem(
            title: "Быстрые шаблоны (F3)",
            action: #selector(openQuickSnippets),
            keyEquivalent: ""
        )
        snippetsItem.target = self
        menu.addItem(snippetsItem)

        let instantItem = NSMenuItem(
            title: "Мгновенный перевод (F1)",
            action: #selector(instantTranslate),
            keyEquivalent: ""
        )
        instantItem.target = self
        menu.addItem(instantItem)

        let translatorItem = NSMenuItem(
            title: "Оверлей переводчика (F4)",
            action: #selector(openTranslator),
            keyEquivalent: ""
        )
        translatorItem.target = self
        menu.addItem(translatorItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Main Window
        let managerItem = NSMenuItem(
            title: "Менеджер сниппетов...",
            action: #selector(openManagerWindow),
            keyEquivalent: ","
        )
        managerItem.target = self
        menu.addItem(managerItem)

        // 3. Accessibility status
        let isTrusted = coordinator.textIO.isAccessibilityGranted()
        let permTitle = isTrusted ? "✓ Доступ Accessibility: Разрешен" : "⚠️ Требуется доступ Accessibility..."
        let permItem = NSMenuItem(
            title: permTitle,
            action: isTrusted ? nil : #selector(requestAccessibility),
            keyEquivalent: ""
        )
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Quit
        let quitItem = NSMenuItem(
            title: "Завершить TextRotator",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openQuickSnippets() {
        Task {
            await coordinator.toggleQuickSnippetsOverlay()
        }
    }

    @objc private func instantTranslate() {
        Task {
            await coordinator.performInstantTranslateAndReplace()
        }
    }

    @objc private func openTranslator() {
        Task {
            await coordinator.showTranslatorOverlay()
        }
    }

    @objc private func openManagerWindow() {
        WindowManager.shared.openManagerWindow(coordinator: coordinator)
    }

    @objc private func requestAccessibility() {
        coordinator.textIO.promptAccessibilityPermission()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
