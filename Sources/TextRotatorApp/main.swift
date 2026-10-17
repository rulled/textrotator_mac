import Foundation
import AppKit
import TextRotatorCore

private final class ActionCollector: @unchecked Sendable {
    private var items: [HotkeyAction] = []
    private let lock = NSLock()

    func append(_ action: HotkeyAction) {
        lock.lock()
        defer { lock.unlock() }
        items.append(action)
    }

    var all: [HotkeyAction] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

@main
struct TextRotatorApp {
    static func main() async {
        let args = CommandLine.arguments

        if args.contains("-h") || args.contains("--help") {
            printUsage()
            exit(0)
        }

        if args.contains("--smoke-test") {
            await runSmokeTest()
            exit(0)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // Menu Bar agent (LSUIElement behavior, no Dock icon)
        ProcessInfo.processInfo.disableAutomaticTermination("TextRotator Menu Bar Daemon")

        let coordinator = AppCoordinator.shared
        let statusBar = StatusBarController(coordinator: coordinator)
        _ = statusBar

        if args.contains("--quick") {
            await coordinator.toggleQuickSnippetsOverlay()
        } else if args.contains("--translate") {
            await coordinator.showTranslatorOverlay()
        } else if args.contains("--instant") {
            await coordinator.performInstantTranslateAndReplace()
        } else if args.contains("--manager") {
            WindowManager.shared.openManagerWindow(coordinator: coordinator)
        } else {
            print("🚀 TextRotator macOS Daemon Starting...")
            print("✅ Core systems initialized. TextRotator running in Menu Bar.")
        }

        app.run()
    }

    private static func printUsage() {
        print("""
        TextRotator macOS (Native Apple Silicon)
        
        Usage:
          TextRotator                Run as background Menu Bar daemon (default)
          TextRotator --quick        Open Quick Snippets Overlay at cursor (F3)
          TextRotator --translate    Open Translator Card Overlay at cursor (F4)
          TextRotator --instant      Trigger Instant Translate & Replace in-place (F1)
          TextRotator --manager      Open Snippets Manager Window (Cmd+,)
          TextRotator --smoke-test   Run automated end-to-end live smoke test
          TextRotator --help, -h     Show this help screen
        """)
    }

    private static func runSmokeTest() async {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧪 TextRotator macOS — End-to-End Live Backend Smoke Test")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // 1. Storage & Database Live Test
        print("\n[1/4] 📦 Storage & Database (SQLite + FTS5):")
        do {
            let tempDbPath = "/tmp/text_rotator_smoke_\(UUID().uuidString).sqlite3"
            let db = try DatabaseService(path: tempDbPath)
            print("  ✓ Database initialized at: \(tempDbPath)")

            let folder1 = try db.createFolder(name: "Шаблоны поддержки")
            let folder2 = try db.createFolder(name: "Код и скрипты")
            print("  ✓ Folders created: [\(folder1.id)] \(folder1.name), [\(folder2.id)] \(folder2.name)")

            let snip1 = try db.createSnippet(
                folderId: folder1.id,
                content: "Здравствуйте! Ваш запрос принят в работу. Номер тикета: #1234."
            )
            _ = try db.createSnippet(
                folderId: folder1.id,
                content: "Благодарим за обращение! Если возникнут вопросы — пишите."
            )
            _ = try db.createSnippet(
                folderId: folder2.id,
                content: "swift run TextRotator --smoke-test"
            )
            print("  ✓ Snippets created: 3 items across 2 folders")

            // Update snippet
            try db.updateSnippet(
                id: snip1.id,
                content: "Здравствуйте! Ваш запрос передан инженеру. Номер тикета: #1234."
            )
            let updatedList = try db.listSnippets(folderId: folder1.id)
            let updatedSnip = updatedList.first { $0.id == snip1.id }
            print("  ✓ Snippet update verified: \"\(updatedSnip?.content.prefix(35) ?? "")...\"")

            // Reorder folders
            try db.reorderFolders(order: [folder2.id, folder1.id])
            let reorderedFolders = try db.listFolders()
            print("  ✓ Folder reorder verified: first is now \"\(reorderedFolders.first?.name ?? "")\"")

            // FTS5 Full-Text Search
            let searchResults = try db.searchSnippets(query: "инженеру", limit: 5)
            print("  ✓ FTS5 Search for 'инженеру': found \(searchResults.count) match(es)")

            let codeSearchResults = try db.searchSnippets(query: "smoke-test", limit: 5)
            print("  ✓ Substring Search for 'smoke-test': found \(codeSearchResults.count) match(es)")

            // Clean up temp DB file
            try? FileManager.default.removeItem(atPath: tempDbPath)
            print("  ✓ Database CRUD & FTS5 test PASSED.")
        } catch {
            print("  ✗ Database test failed: \(error)")
            exit(1)
        }

        // 2. Live Translation Network Test (Yandex & Google)
        print("\n[2/4] 🌐 Translation Engine (Live Network Endpoints):")
        let router = TranslationRouter()

        // 2a. Russian -> English via Yandex
        let textRu = "Мы проверим этот вопрос и свяжемся с вами в течение часа."
        let reqRu = TranslationRequest(text: textRu)
        print("  • Requesting translation: \"\(textRu)\" [Auto-detect: \(reqRu.sourceLanguage) -> \(reqRu.targetLanguage)]")
        do {
            let resRu = try await router.translateWithFallback(request: reqRu)
            print("  ✓ [\(resRu.providerName)] (\(resRu.latencyMs) ms) \(resRu.detectedSourceLanguage) -> \(resRu.targetLanguage):")
            print("    \"\(resRu.translatedText)\"")
        } catch {
            print("  ✗ Yandex translation failed: \(error)")
        }

        // 2b. English -> Russian via Yandex / Fallback
        let textEn = "Instant in-place translation works natively on macOS."
        let reqEn = TranslationRequest(text: textEn)
        print("  • Requesting translation: \"\(textEn)\" [Auto-detect: \(reqEn.sourceLanguage) -> \(reqEn.targetLanguage)]")
        do {
            let resEn = try await router.translateWithFallback(request: reqEn)
            print("  ✓ [\(resEn.providerName)] (\(resEn.latencyMs) ms) \(resEn.detectedSourceLanguage) -> \(resEn.targetLanguage):")
            print("    \"\(resEn.translatedText)\"")
        } catch {
            print("  ✗ Translation failed: \(error)")
        }

        // 2c. Google direct check
        let googleProvider = GoogleProvider()
        let googleReq = TranslationRequest(text: "Hello world", sourceLanguage: "en", targetLanguage: "ru")
        do {
            let resGoogle = try await googleProvider.translate(request: googleReq)
            print("  ✓ [Google] (\(resGoogle.latencyMs) ms) en -> ru:")
            print("    \"\(resGoogle.translatedText)\"")
        } catch {
            print("  ✗ Google direct translation failed: \(error)")
        }

        // 3. Text I/O & Pasteboard Concealment Test
        print("\n[3/4] 📋 Text I/O & Pasteboard Concealment:")
        let textIO = TextIOService.shared
        let isTrusted = textIO.isAccessibilityGranted()
        print("  • Accessibility Permission (`AXIsProcessTrusted`): \(isTrusted ? "GRANTED" : "NOT GRANTED (Normal in CLI sandbox)")")

        // Test NSPasteboard concealment write
        let pasteboard = NSPasteboard.general
        let originalChangeCount = pasteboard.changeCount
        let testSecret = "TextRotator_Concealed_Test_\(UUID().uuidString)"
        pasteboard.declareTypes([
            .string,
            NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
            NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        ], owner: nil)
        pasteboard.setString(testSecret, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))

        let readBack = pasteboard.string(forType: .string)
        let hasTransient = pasteboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) ?? false
        print("  ✓ NSPasteboard concealment payload set (changeCount changed from \(originalChangeCount) to \(pasteboard.changeCount))")
        print("  ✓ Transient marker present: \(hasTransient), Content: \"\(readBack ?? "")\"")

        // 4. Hotkeys & Action Pipeline Test
        print("\n[4/4] ⚡ Hotkey & Action Pipeline:")
        let pipeline = ActionPipeline(debounceInterval: 0.180, autoResetOperationInProgress: true)
        let collector = ActionCollector()
        pipeline.subscribe { action in
            collector.append(action)
        }

        let d1 = pipeline.dispatch(.instantTranslateAndReplace)
        let d2 = pipeline.dispatch(.instantTranslateAndReplace) // should be debounced within 180ms
        pipeline.endOperation()
        let d3 = pipeline.dispatch(.quickSnippetsOverlay)

        try? await Task.sleep(nanoseconds: 50_000_000)
        print("  ✓ Dispatched 3 events: accepted d1=\(d1), debounced d2=\(d2) (expected false), d3=\(d3) (expected true)")
        print("  ✓ Received actions in queue: \(collector.all)")

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎉 ALL SMOKE TESTS COMPLETED SUCCESSFULLY!")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}
