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
        seedInitialDataIfNeeded()
    }

    // MARK: - Setup & Hotkeys

    private func setupHotkeys() {
        hotkeyService.pipeline.setAsyncHandler { [weak self] action in
            guard let self else { return }
            await self.handleAction(action)
        }
        try? hotkeyService.start()
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

        let cardSize = NSSize(width: 380, height: 210)
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

    public func toggleCursorTranslateMode() {
        isCursorTranslateEnabled.toggle()
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

    private static let seedKey = "com.textrotator.has_seeded_initial_data"

    private func seedInitialDataIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.seedKey) else { return }
        do {
            let f1 = try database.createFolder(name: "Клиентская поддержка")
            _ = try database.createSnippet(folderId: f1.id, content: "Здравствуйте! Чем я могу вам помочь?")
            _ = try database.createSnippet(folderId: f1.id, content: "Спасибо за ожидание! Ваш запрос передан техническому специалисту, ответим в течение 15 минут.")
            _ = try database.createSnippet(folderId: f1.id, content: "Уточните, пожалуйста, номер вашего заказа или привязанный номер телефона.")
            _ = try database.createSnippet(folderId: f1.id, content: "Проблема устранена! Пожалуйста, проверьте работу сервиса и сообщите нам.")
            _ = try database.createSnippet(folderId: f1.id, content: "Благодарим за обращение! Если у вас появятся дополнительные вопросы — пишите, мы всегда на связи.")

            let f2 = try database.createFolder(name: "Оплата и счета")
            _ = try database.createSnippet(folderId: f2.id, content: "Мы предоставляем 100% гарантию возврата средств в течение 14 дней с момента покупки.")
            _ = try database.createSnippet(folderId: f2.id, content: "Ссылка на оплату сформирована и направлена в ваш личный кабинет.")
            _ = try database.createSnippet(folderId: f2.id, content: "Реквизиты для оплаты: ООО «Текст Ротатор», ИНН 7701234567, р/с 40702810900000012345.")
            _ = try database.createSnippet(folderId: f2.id, content: "Мы принимаем карты МИР, Visa, MasterCard, а также оплату через СБП без комиссии 0%.")
            _ = try database.createSnippet(folderId: f2.id, content: "Чек и закрывающие документы доступны для скачивания в формате PDF в профиле.")

            let f3 = try database.createFolder(name: "English Support")
            _ = try database.createSnippet(folderId: f3.id, content: "Hello! How can I assist you today?")
            _ = try database.createSnippet(folderId: f3.id, content: "Thank you for reaching out! We are currently investigating this issue and will update you shortly.")
            _ = try database.createSnippet(folderId: f3.id, content: "Could you please provide your order ID or account email address?")
            _ = try database.createSnippet(folderId: f3.id, content: "We have issued a 100% refund for your purchase. It should appear in your account within 3-5 business days.")
            _ = try database.createSnippet(folderId: f3.id, content: "Everything is sorted out! Feel free to contact us if you need any further assistance.")

            let f4 = try database.createFolder(name: "Код и скрипты")
            _ = try database.createSnippet(folderId: f4.id, content: "git add . && git commit -m \"feat: update search engine\" && git push origin main")
            _ = try database.createSnippet(folderId: f4.id, content: "curl -X POST https://api.textrotator.app/v1/translate -H \"Content-Type: application/json\"")
            _ = try database.createSnippet(folderId: f4.id, content: "docker compose up -d --build && docker compose logs -f")
            _ = try database.createSnippet(folderId: f4.id, content: "npm run build && npm run test:coverage")
            _ = try database.createSnippet(folderId: f4.id, content: "// TODO: optimize database indexes for FTS5 full-text query")

            UserDefaults.standard.set(true, forKey: Self.seedKey)
            reloadDatabaseData()
        } catch {
            print("Failed to seed database: \(error)")
        }
    }
}
