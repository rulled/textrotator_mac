import Foundation
import AppKit
import SwiftUI
import TextRotatorCore

@MainActor
public final class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()

    public let database: DatabaseServiceProtocol
    public let translationRouter: TranslationRouterProtocol
    public let textIO: TextIOServiceProtocol
    public let hotkeyService: HotkeyService
    public let backupService = BackupService()

    // Active overlays
    public var quickSnippetsPanel: FloatingPanelController?
    public var translatorPanel: FloatingPanelController?

    // Remembered target application before overlay popped up
    private var lastExternalApp: NSRunningApplication?
    // Micro-indicator for F1 instant translation
    private let translationIndicator = TranslationIndicatorController()

    // Cursor Translate Mode (Feature 4: Auto-translate on mouse selection release)
    @Published public var isCursorTranslateEnabled: Bool = false
    private var cursorWatcher: CursorSelectionWatcher?


    // State for Overlays
    @Published public var folders: [FolderWithSnippets] = []
    @Published public var translatorSourceText: String = ""
    @Published public var translatorResultText: String = ""
    @Published public var translatorSourceLang: String = "auto"
    @Published public var translatorTargetLang: String = "ru"
    @Published public var isTranslating: Bool = false
    @Published public var activeProviderName: String = "Yandex"
    @Published public var lastLatencyMs: Int? = nil
    public init(
        database: DatabaseServiceProtocol? = nil,
        translationRouter: TranslationRouterProtocol = TranslationRouter(),
        textIO: TextIOServiceProtocol = TextIOService.shared,
        hotkeyService: HotkeyService = HotkeyService()
    ) {
        if let database {
            self.database = database
        } else {
            do {
                self.database = try DatabaseService()
            } catch {
                print("Failed to initialize primary database, falling back to in-memory: \(error)")
                self.database = try! DatabaseService.inMemory()
            }
        }
        self.translationRouter = translationRouter
        self.textIO = textIO
        self.hotkeyService = hotkeyService

        setupHotkeys()
        reloadDatabaseData()
        restoreCursorTranslateState()
        // Prompt accessibility on startup if not yet granted so app appears in System Settings
        if !textIO.isAccessibilityGranted() {
            textIO.promptAccessibilityPermission()
        }
        // Background update check after launch
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if UpdateService.shared.isAutomaticCheckEnabled {
                UpdateService.shared.checkForUpdates(isUserInitiated: false)
            }
        }
    }

    // MARK: - Setup & Hotkeys

    private func setupHotkeys() {
        var config = HotkeyConfiguration.default
        for action in HotkeyAction.allCases {
            if UserDefaults.standard.object(forKey: "hotkey_code_\(action.rawValue)") != nil {
                let code = UInt32(UserDefaults.standard.integer(forKey: "hotkey_code_\(action.rawValue)"))
                let mods = KeyModifiers(rawValue: UInt32(UserDefaults.standard.integer(forKey: "hotkey_mods_\(action.rawValue)")))
                config.setKeyCombo(KeyCombo(keyCode: code, modifiers: mods), for: action)
            } else if let saved = UserDefaults.standard.string(forKey: "hotkey_\(action.rawValue)"),
                      let combo = KeyCombo(string: saved) {
                config.setKeyCombo(combo, for: action)
            }
        }
        try? hotkeyService.updateConfiguration(config)

        hotkeyService.pipeline.setAsyncHandler { [weak self] action in
            guard let self else { return }
            await self.handleAction(action)
        }
        try? hotkeyService.start()
    }

    public func updateHotkey(for action: HotkeyAction, combo: KeyCombo) {
        do {
            try hotkeyService.register(action: action, combo: combo)
            UserDefaults.standard.set(Int(combo.keyCode), forKey: "hotkey_code_\(action.rawValue)")
            UserDefaults.standard.set(Int(combo.modifiers.rawValue), forKey: "hotkey_mods_\(action.rawValue)")
            UserDefaults.standard.set(combo.displayString, forKey: "hotkey_\(action.rawValue)")
            objectWillChange.send()
            AppTheme.hapticSuccess()
        } catch {
            print("Failed to register hotkey: \(error)")
        }
    }

    public func resetHotkeysToDefault() {
        do {
            try hotkeyService.updateConfiguration(.default)
            for action in HotkeyAction.allCases {
                UserDefaults.standard.removeObject(forKey: "hotkey_\(action.rawValue)")
                UserDefaults.standard.removeObject(forKey: "hotkey_code_\(action.rawValue)")
                UserDefaults.standard.removeObject(forKey: "hotkey_mods_\(action.rawValue)")
            }
            objectWillChange.send()
            AppTheme.hapticClick()
        } catch {
            print("Failed to reset hotkeys: \(error)")
        }
    }

    public func currentKeyCombo(for action: HotkeyAction) -> KeyCombo {
        hotkeyService.configuration.keyCombo(for: action) ?? HotkeyConfiguration.default.keyCombo(for: action) ?? KeyCombo(keyCode: KeyCode.f1)
    }

    public func handleAction(_ action: HotkeyAction) async {
        switch action {
        case .quickSnippetsOverlay:
            await toggleQuickSnippetsOverlay()
        case .instantTranslateAndReplace:
            await performInstantTranslateAndReplace()
        case .translatorOverlay:
            await showTranslatorOverlay()
        case .cursorTranslateToggle:
            toggleCursorTranslateMode()
        }
    }

    public func rememberForegroundApp() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.lastExternalApp = frontmost
        }
    }

    public func restoreForegroundApp() {
        if let target = lastExternalApp {
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: target)
                target.activate()
            } else {
                target.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    // MARK: - Instant Translate & Replace (F1)

    public func performInstantTranslateAndReplace() async {
        rememberForegroundApp()

        guard let selectedText = await textIO.captureSelectedText(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Instant translate: No selected text captured")
            return
        }

        // Show micro-indicator near cursor during translation
        translationIndicator.showNearCursor()
        defer {
            translationIndicator.dismiss()
        }

        let request = TranslationRequest(text: selectedText)
        do {
            let result = try await translationRouter.translateWithFallback(request: request)
            translationIndicator.dismiss()
            restoreForegroundApp()
            NSApp.deactivate()
            // Delay to ensure target app has focus
            try? await Task.sleep(nanoseconds: 80_000_000)
            try await textIO.insertText(result.translatedText)
        } catch {
            print("Instant translate error: \(error)")
        }
    }

    // MARK: - Quick Snippets Overlay (F3)

    public func toggleQuickSnippetsOverlay() async {
        reloadDatabaseData()

        if quickSnippetsPanel?.isVisible == true {
            quickSnippetsPanel?.close()
            return
        }

        rememberForegroundApp()
        let navState = QuickSnippetsNavigationState(folders: self.folders)
        let panel = FloatingPanelController(title: "Snippets")
        let view = QuickSnippetsView(coordinator: self, navState: navState)
        let size = NSSize(width: 440, height: 350)
        panel.setContent(view: view, size: size)
        panel.positionNearCursor(size: size)

        panel.panel.onKeyDown = { [weak self, weak navState] event in
            guard let self, let navState else { return false }
            let result = navState.handleKeyDown(keyCode: event.keyCode)
            switch result {
            case .handled:
                AppTheme.hapticClick()
                return true
            case .ignored:
                return false
            case .insertSnippet(let text):
                self.insertSnippetText(text)
                return true
            case .closeOverlay:
                self.quickSnippetsPanel?.close()
                return true
            }
        }

        panel.onClose = { [weak self] in
            self?.quickSnippetsPanel = nil
            self?.restoreForegroundApp()
        }

        self.quickSnippetsPanel = panel
        panel.show()
    }
    public func insertSnippetText(_ text: String) {
        quickSnippetsPanel?.dismissImmediately()
        quickSnippetsPanel = nil

        restoreForegroundApp()
        NSApp.deactivate()

        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            do {
                try await textIO.insertText(text)
            } catch {
                print("Failed to insert snippet: \(error)")
            }
        }
    }

    // MARK: - Translator Overlay (F4)

    public func showTranslatorOverlay(text: String? = nil) async {
        if translatorPanel?.isVisible == true {
            translatorPanel?.close()
            return
        }

        rememberForegroundApp()

        let captured: String
        if let text {
            captured = text
        } else {
            captured = await textIO.captureSelectedText() ?? ""
        }
        self.translatorSourceText = captured
        self.translatorResultText = ""
        self.isTranslating = true

        let initialHeight = Self.optimalTranslatorHeight(for: captured)
        let cardSize = NSSize(width: 380, height: initialHeight)
        let panel = FloatingPanelController(title: "Translator")
        let view = TranslatorCardView(coordinator: self)
        panel.setContent(view: view, size: cardSize)
        panel.positionNearCursor(size: cardSize)
        panel.onClose = { [weak self] in
            self?.translatorPanel = nil
            self?.restoreForegroundApp()
        }

        self.translatorPanel = panel
        panel.show()

        if !captured.isEmpty {
            await requestTranslation(text: captured)
        } else {
            self.isTranslating = false
        }
    }

    public func toggleCursorTranslateMode(showFeedback: Bool = true) {
        isCursorTranslateEnabled.toggle()
        UserDefaults.standard.set(isCursorTranslateEnabled, forKey: "isCursorTranslateEnabled")
        if showFeedback {
            translationIndicator.showNearCursor(
                state: isCursorTranslateEnabled ? .checkmark : .cross,
                autoDismissDelay: 0.85
            )
            AppTheme.hapticSuccess()
        }
        if isCursorTranslateEnabled {
            if cursorWatcher == nil {
                cursorWatcher = CursorSelectionWatcher(textIO: textIO) { [weak self] selectedText in
                    guard let self else { return }
                    Task {
                        await self.showTranslatorOverlay(text: selectedText)
                    }
                }
            }
            cursorWatcher?.start()
        } else {
            cursorWatcher?.stop()
        }
    }

    private func restoreCursorTranslateState() {
        let enabled = UserDefaults.standard.bool(forKey: "isCursorTranslateEnabled")
        self.isCursorTranslateEnabled = enabled
        if enabled {
            cursorWatcher = CursorSelectionWatcher(textIO: textIO) { [weak self] selectedText in
                guard let self else { return }
                Task {
                    await self.showTranslatorOverlay(text: selectedText)
                }
            }
            cursorWatcher?.start()
        }
    }

    public func requestTranslation(text: String, preferredProvider: String? = nil) async {
        self.isTranslating = true
        let req = TranslationRequest(text: text)
        self.translatorSourceLang = req.sourceLanguage
        self.translatorTargetLang = req.targetLanguage

        do {
            let result = try await translationRouter.translate(
                request: req,
                preferredProvider: preferredProvider ?? activeProviderName
            )
            self.translatorResultText = result.translatedText
            self.translatorSourceLang = result.detectedSourceLanguage
            self.translatorTargetLang = result.targetLanguage
            self.activeProviderName = result.providerName
            self.lastLatencyMs = result.latencyMs
            let height = Self.optimalTranslatorHeight(for: self.translatorResultText)
            self.translatorPanel?.animateResize(to: NSSize(width: 380, height: height))
        } catch {
            // Fallback
            do {
                let fallbackResult = try await translationRouter.translateWithFallback(request: req)
                self.translatorResultText = fallbackResult.translatedText
                self.translatorSourceLang = fallbackResult.detectedSourceLanguage
                self.translatorTargetLang = fallbackResult.targetLanguage
                self.activeProviderName = fallbackResult.providerName
                self.lastLatencyMs = fallbackResult.latencyMs
            } catch {
                self.translatorResultText = "Ошибка перевода: \(error.localizedDescription)"
            }
        }
        self.isTranslating = false
    }

    public static func optimalTranslatorHeight(for text: String) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        if count == 0 {
            return 145
        } else if count <= 30 && !trimmed.contains("\n") {
            return 130 // Compact for single word / short phrase
        } else if count <= 90 {
            return 165
        } else if count <= 220 {
            return 210
        } else if count <= 420 {
            return 260
        } else {
            return 320 // Max height, scrollable
        }
    }

    public func insertCurrentTranslation() {
        let text = translatorResultText
        translatorPanel?.dismissImmediately()
        translatorPanel = nil

        guard !text.isEmpty else { return }
        restoreForegroundApp()
        NSApp.deactivate()

        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            try? await textIO.insertText(text)
        }
    }

    // MARK: - Database Helpers

    public func reloadDatabaseData() {
        do {
            self.folders = try database.listFoldersWithSnippets()
        } catch {
            print("Failed to load folders from database: \(error)")
        }
    }

    // MARK: - Config Import / Export (TextRotator cross-compatible)

    /// Mapping between original app hotkey names and our actions.
    private static let backupHotkeyActions: [String: HotkeyAction] = [
        "hotkey.rotation": .quickSnippetsOverlay,
        "hotkey.translate": .translatorOverlay,
        "hotkey.instant_translate": .instantTranslateAndReplace,
        "hotkey.cursor_translate": .cursorTranslateToggle
    ]

    /// Export the full configuration in the original TextRotator backup format.
    public func exportConfiguration() throws -> Data {
        var folderPayloads: [ImportFolderPayload] = []
        for folder in try database.listFoldersWithSnippets() {
            folderPayloads.append(ImportFolderPayload(
                name: folder.name,
                snippets: folder.snippets.map(\.content)
            ))
        }

        let hotkeys = BackupHotkeys(
            rotation: exportHotkeyString(for: .quickSnippetsOverlay),
            translation: exportHotkeyString(for: .translatorOverlay),
            instant: exportHotkeyString(for: .instantTranslateAndReplace),
            cursor: exportHotkeyString(for: .cursorTranslateToggle)
        )

        var settings: [String: String] = [:]
        settings["provider.primary"] = activeProviderName
        settings["cursor.translate_mode.enabled"] = isCursorTranslateEnabled ? "1" : "0"
        settings["theme.active"] = colorSchemeSettingValue()

        let backup = backupService.makeBackup(
            folders: folderPayloads,
            hotkeys: hotkeys,
            settings: settings
        )
        return try backupService.encode(backup)
    }

    /// Human-readable hotkey string ("F3", "Cmd+Shift+V", "Alt+Comma") matching
    /// the original application's notation (written by its settings UI).
    private func exportHotkeyString(for action: HotkeyAction) -> String {
        let combo = currentKeyCombo(for: action)
        var parts: [String] = []
        if combo.modifiers.contains(.command) { parts.append("Cmd") }
        if combo.modifiers.contains(.option) { parts.append("Alt") }
        if combo.modifiers.contains(.shift) { parts.append("Shift") }
        if combo.modifiers.contains(.control) { parts.append("Ctrl") }

        let keyName = KeyCode.name(for: combo.keyCode)
        // Original app writes plain "F3"; punctuation names need single-char form.
        let normalizedKey: String
        switch keyName {
        case "Space": normalizedKey = "Space"
        case "Return": normalizedKey = "Enter"
        case "Esc": normalizedKey = "Escape"
        default: normalizedKey = keyName
        }
        parts.append(normalizedKey)
        return parts.joined(separator: "+")
    }

    /// Import a backup produced by the original app or by TextRotator macOS.
    /// - Parameters:
    ///   - data: raw JSON bytes.
    ///   - replaceExisting: when true (default) the folders store is wiped before import.
    /// - Returns: summary of what was imported.
    @discardableResult
    public func importConfiguration(data: Data, replaceExisting: Bool = true) throws -> ImportResult {
        let parsed = try backupService.parse(data: data)

        var foldersImported = 0
        var snippetsImported = 0

        if replaceExisting {
            for folder in try database.listFoldersWithSnippets() {
                try database.deleteFolder(id: folder.id)
            }
        }

        for payload in parsed.folders {
            let folder = try database.createFolder(name: payload.name)
            foldersImported += 1
            for snippet in payload.snippets {
                _ = try database.createSnippet(folderId: folder.id, content: snippet)
                snippetsImported += 1
            }
        }
        reloadDatabaseData()

        // Hotkeys: original stores "F3" / "Alt+Comma" style strings.
        var hotkeysImported = 0
        if let hk = parsed.hotkeys {
            let pairs: [(String?, HotkeyAction)] = [
                (hk.rotation, .quickSnippetsOverlay),
                (hk.translation, .translatorOverlay),
                (hk.instant, .instantTranslateAndReplace),
                (hk.cursor, .cursorTranslateToggle)
            ]
            for (value, action) in pairs {
                guard let value, !value.isEmpty else { continue }
                if let combo = KeyCombo(string: value) {
                    try? hotkeyService.register(action: action, combo: combo)
                    UserDefaults.standard.set(Int(combo.keyCode), forKey: "hotkey_code_\(action.rawValue)")
                    UserDefaults.standard.set(Int(combo.modifiers.rawValue), forKey: "hotkey_mods_\(action.rawValue)")
                    UserDefaults.standard.set(combo.displayString, forKey: "hotkey_\(action.rawValue)")
                    hotkeysImported += 1
                }
            }
            objectWillChange.send()
        }

        // Settings: apply the subset we natively support.
        var settingsApplied = 0
        if let settings = parsed.settings {
            // Primary provider
            if let primary = settings["provider.primary"],
               primary == "Yandex" || primary == "Google" {
                activeProviderName = primary
                settingsApplied += 1
            }

            // Cursor translate mode
            if let enabled = settings["cursor.translate_mode.enabled"] {
                let target: Bool
                switch enabled {
                case "1", "true", "yes": target = true
                case "0", "false", "no": target = false
                default: target = isCursorTranslateEnabled
                }
                if target != isCursorTranslateEnabled {
                    toggleCursorTranslateMode(showFeedback: false)
                }
                settingsApplied += 1
            }
        }

        return ImportResult(
            foldersImported: foldersImported,
            snippetsImported: snippetsImported,
            hotkeysImported: hotkeysImported,
            settingsImported: settingsApplied
        )
    }

    private func colorSchemeSettingValue() -> String {
        switch NSApp.effectiveAppearance.bestMatch(from: [.aqua, .vibrantDark]) {
        case .aqua: return "light"
        default: return "dark"
        }
    }
}
