import XCTest
@testable import TextRotatorCore

final class SmartSearchTests: XCTestCase {

    func testKeyboardLayoutInversion() {
        XCTAssertEqual(SmartSearchEngine.invertKeyboardLayout("ghbdtn"), "привет")
        XCTAssertEqual(SmartSearchEngine.invertKeyboardLayout("рудз"), "help")
        XCTAssertEqual(SmartSearchEngine.invertKeyboardLayout("Cnfhn"), "Старт")
        XCTAssertEqual(SmartSearchEngine.invertKeyboardLayout("123"), "123")
    }

    func testNormalization() {
        XCTAssertEqual(SmartSearchEngine.normalize("  Ёлка и Ещё  "), "елка и еще")
    }

    func testExactAndPrefixMatching() {
        let exactScore = SmartSearchEngine.calculateScore(query: "Шаблоны", candidate: "шаблоны")
        let prefixScore = SmartSearchEngine.calculateScore(query: "Шаб", candidate: "Шаблоны поддержки")
        let substringScore = SmartSearchEngine.calculateScore(query: "поддержки", candidate: "Шаблоны поддержки")

        XCTAssertGreaterThan(exactScore, prefixScore)
        XCTAssertGreaterThan(prefixScore, substringScore)
        XCTAssertGreaterThan(substringScore, 0.0)
    }

    func testFuzzySubsequenceMatching() {
        let fzyScore = SmartSearchEngine.calculateScore(query: "пдд", candidate: "Шаблоны поддержки")
        XCTAssertGreaterThan(fzyScore, 50.0)
    }

    func testDamerauLevenshteinTypoTolerance() {
        // Transposition: 'здравсвуйте' missing 'т'
        let typoScore = SmartSearchEngine.calculateScore(query: "здравсвуйте", candidate: "Здравствуйте! Чем могу вам помочь?")
        XCTAssertGreaterThan(typoScore, 0.0)

        // One typo letter: 'инжинер' -> 'инженер'
        let typoWordScore = SmartSearchEngine.calculateScore(query: "инжинер", candidate: "Запрос передан старшему инженеру.")
        XCTAssertGreaterThan(typoWordScore, 0.0)

        // Exact distance function checks
        XCTAssertEqual(SmartSearchEngine.damerauLevenshteinDistance("кот", "ток"), 2) // substitution + substitution or deletion + insertion
        XCTAssertEqual(SmartSearchEngine.damerauLevenshteinDistance("кот", "кто"), 1) // adjacent transposition
        XCTAssertEqual(SmartSearchEngine.damerauLevenshteinDistance("текст", "ткст"), 1) // deletion
    }

    func testDualLayoutSearchCorrection() {
        // User typed 'ghbdtn' in English layout when looking for 'Привет'
        let score = SmartSearchEngine.calculateScore(query: "ghbdtn", candidate: "Привет, как твои дела?")
        XCTAssertGreaterThan(score, 100.0)

        // User typed 'рудз' in Russian layout when looking for 'help'
        let scoreEn = SmartSearchEngine.calculateScore(query: "рудз", candidate: "Online help and support")
        XCTAssertGreaterThan(scoreEn, 100.0)
    }

    func testSymbolsAndNumbersPreservation() {
        let scoreNumbers = SmartSearchEngine.calculateScore(query: "100%", candidate: "Гарантия возврата 100% средств.")
        XCTAssertGreaterThan(scoreNumbers, 100.0)

        let scoreCode = SmartSearchEngine.calculateScore(query: "// TODO", candidate: "// TODO: implement network fallback")
        XCTAssertGreaterThan(scoreCode, 100.0)
    }

    func testUnifiedSearchFoldersAndSnippets() {
        let folders = [
            FolderWithSnippets(
                id: 1,
                name: "Шаблоны поддержки",
                position: 0,
                snippets: [
                    SnippetItem(id: 101, folderId: 1, content: "Здравствуйте! Чем я могу вам помочь?", position: 0),
                    SnippetItem(id: 102, folderId: 1, content: "Направьте, пожалуйста, номер заказа.", position: 1)
                ]
            ),
            FolderWithSnippets(
                id: 2,
                name: "Код и скрипты",
                position: 1,
                snippets: [
                    SnippetItem(id: 201, folderId: 2, content: "git commit -m 'feat: update search'", position: 0),
                    SnippetItem(id: 202, folderId: 2, content: "npm run build --release", position: 1)
                ]
            )
        ]

        // 1. Empty query returns all folders in position order
        let emptyResults = SmartSearchEngine.search(query: "", in: folders)
        XCTAssertEqual(emptyResults.count, 2)
        if case .folder(let f, _) = emptyResults[0] {
            XCTAssertEqual(f.name, "Шаблоны поддержки")
        } else {
            XCTFail("Expected folder item")
        }

        // 2. Query matching folder name
        let folderResults = SmartSearchEngine.search(query: "скрипты", in: folders)
        XCTAssertFalse(folderResults.isEmpty)
        if case .folder(let f, _) = folderResults[0] {
            XCTAssertEqual(f.name, "Код и скрипты")
        } else {
            XCTFail("Expected top result to be folder 'Код и скрипты'")
        }

        // 3. Query matching snippet text in English layout ('yjvth' -> 'номер')
        let snippetLayoutResults = SmartSearchEngine.search(query: "yjvth", in: folders)
        XCTAssertFalse(snippetLayoutResults.isEmpty)
        if case .snippet(let s, let folderName, let folderId, _) = snippetLayoutResults[0] {
            XCTAssertEqual(s.id, 102)
            XCTAssertEqual(folderName, "Шаблоны поддержки")
            XCTAssertEqual(folderId, 1)
        } else {
            XCTFail("Expected snippet result with folder badge")
        }

        // 4. Query matching symbols/command
        let codeResults = SmartSearchEngine.search(query: "git commit", in: folders)
        XCTAssertFalse(codeResults.isEmpty)
        if case .snippet(let s, _, _, _) = codeResults[0] {
            XCTAssertTrue(s.content.contains("git commit"))
        } else {
            XCTFail("Expected git commit snippet")
        }
    }
}
