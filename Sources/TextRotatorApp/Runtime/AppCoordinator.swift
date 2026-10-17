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
            print("Cursor translate toggle requested")
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
            target.activate()
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

        let request = TranslationRequest(text: selectedText)
        do {
            let result = try await translationRouter.translateWithFallback(request: request)
            restoreForegroundApp()
            // Slight delay to ensure target app has focus
            try? await Task.sleep(nanoseconds: 60_000_000)
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
            restoreForegroundApp()
            return
        }

        rememberForegroundApp()
        let panel = FloatingPanelController(title: "Snippets")
        let view = QuickSnippetsView(coordinator: self)
        panel.setContent(view: view, size: NSSize(width: 380, height: 320))
        panel.positionNearCursor(size: NSSize(width: 380, height: 320))
        panel.show()
        self.quickSnippetsPanel = panel
    }

    public func insertSnippetText(_ text: String) {
        quickSnippetsPanel?.close()
        restoreForegroundApp()

        Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            try? await textIO.insertText(text)
        }
    }

    // MARK: - Translator Overlay (F4)

    public func showTranslatorOverlay() async {
        rememberForegroundApp()

        let captured = await textIO.captureSelectedText() ?? ""
        self.translatorSourceText = captured
        self.translatorResultText = ""
        self.isTranslating = true

        let panel = FloatingPanelController(title: "Translator")
        let view = TranslatorCardView(coordinator: self)
        panel.setContent(view: view, size: NSSize(width: 420, height: 260))
        panel.positionNearCursor(size: NSSize(width: 420, height: 260))
        panel.show()
        self.translatorPanel = panel

        if !captured.isEmpty {
            await requestTranslation(text: captured)
        } else {
            self.isTranslating = false
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
        translatorPanel?.close()
        restoreForegroundApp()

        guard !text.isEmpty else { return }
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
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

    private func seedInitialDataIfNeeded() {
        if folders.isEmpty {
            do {
                let f1 = try database.createFolder(name: "Быстрые ответы")
                _ = try database.createSnippet(
                    folderId: f1.id,
                    content: "Здравствуйте! Спасибо за обращение, мы уже изучаем вопрос."
                )
                _ = try database.createSnippet(
                    folderId: f1.id,
                    content: "Готово! Проверьте, пожалуйста, результат и дайте обратную связь."
                )

                let f2 = try database.createFolder(name: "Шаблоны email")
                _ = try database.createSnippet(
                    folderId: f2.id,
                    content: "Добрый день!\n\nВо вложении направляю обновленный отчет.\n\nС уважением,\nКоманда поддержки"
                )

                reloadDatabaseData()
            } catch {
                print("Failed to seed database: \(error)")
            }
        }
    }
}
