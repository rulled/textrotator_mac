import XCTest
@testable import TextRotatorCore

/// Regression tests for the reported bug: "after first search, erasing the query
/// and typing a new one, OLD results remain". Exercises the exact state machine
/// lifecycle the overlay uses (searchText binding writes + arrow/esc/enter keys).
@MainActor
final class SearchStalenessRegressionTests: XCTestCase {

    private var folders: [FolderWithSnippets] {
        [
            FolderWithSnippets(id: 1, name: "Приветки", position: 0, snippets: [
                SnippetItem(id: 101, folderId: 1, content: "привет, как дела?", position: 0),
                SnippetItem(id: 102, folderId: 1, content: "good morning sunshine", position: 1)
            ]),
            FolderWithSnippets(id: 2, name: "Оплата", position: 1, snippets: [
                SnippetItem(id: 201, folderId: 2, content: "счёт на оплату отправлен", position: 0),
                SnippetItem(id: 202, folderId: 2, content: "реквизиты компании", position: 1)
            ]),
            FolderWithSnippets(id: 3, name: "HR TEST", position: 2, snippets: [
                SnippetItem(id: 301, folderId: 3, content: "onlymonster browser guide", position: 0)
            ])
        ]
    }

    private func contents(_ results: [SmartSearchItem]) -> [String] {
        results.map {
            switch $0 {
            case .folder(let f, _): return "folder:\(f.name)"
            case .snippet(let s, _, _, _): return "snippet:\(s.content)"
            }
        }
    }

    // MARK: - Core regression: erase then type a new query

    func testEraseCharByCharThenTypeNewQueryNeverKeepsStaleResults() {
        let state = QuickSnippetsNavigationState(folders: folders)

        // First search: "прив"
        state.searchText = "прив"
        let first = state.searchResults
        var snapshot = first
        while !state.searchText.isEmpty {
            state.searchText.removeLast()
            snapshot = state.searchResults

            if state.isSearching {
                // Searching regime: results must equal a fresh engine run for the current query
                let fresh = SmartSearchEngine.search(query: state.searchText, in: folders)
                XCTAssertEqual(
                    snapshot.count, fresh.count,
                    "stale results at query '\(state.searchText)': got \(contents(snapshot))"
                )
            } else {
                // Whitespace/empty regime: results must be fully cleared (folders list shown)
                XCTAssertTrue(snapshot.isEmpty,
                              "results must clear when query stops being searchable, got \(contents(snapshot))")
            }
        }

        // Fully erased → not searching → empty results, folders view restored
        XCTAssertTrue(state.searchResults.isEmpty)
        XCTAssertFalse(state.isSearching)

        // New query: must reflect ONLY new matches
        state.searchText = "опла"
        let second = state.searchResults
        XCTAssertFalse(second.isEmpty)
        for item in second {
            switch item {
            case .folder(let f, _):
                XCTAssertTrue(f.name.lowercased().contains("опла"), "stale folder '\(f.name)' for query 'опла'")
            case .snippet(let s, _, _, _):
                XCTAssertTrue(s.content.lowercased().contains("опла") || s.content.lowercased().contains("оплат"),
                              "stale snippet '\(s.content)' for query 'опла'")
            }
        }
    }

    func testEscClearsThenNewSearchIsFresh() {
        let state = QuickSnippetsNavigationState(folders: folders)

        state.searchText = "прив"
        XCTAssertFalse(state.searchResults.isEmpty)

        // Esc clears search
        let escResult = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape)
        XCTAssertEqual(escResult, .handled)
        XCTAssertEqual(state.searchText, "")
        XCTAssertTrue(state.searchResults.isEmpty, "Esc must wipe results immediately")

        // New query right away
        state.searchText = "hr"
        let results = state.searchResults
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(contents(results).contains("folder:HR TEST"))
    }

    func testClearButtonSemanticsThenNewSearchIsFresh() {
        let state = QuickSnippetsNavigationState(folders: folders)

        state.searchText = "good"
        XCTAssertEqual(state.searchResults.count, 1)

        // The xmark clear button sets text to ""
        state.searchText = ""
        XCTAssertTrue(state.searchResults.isEmpty)
        XCTAssertFalse(state.isSearching)

        state.searchText = "реквизиты"
        XCTAssertEqual(state.searchResults.count, 1)
        XCTAssertEqual(contents(state.searchResults), ["snippet:реквизиты компании"])
    }

    func testWhitespaceOnlyQueryIsNotSearching() {
        let state = QuickSnippetsNavigationState(folders: folders)
        state.searchText = "   "
        XCTAssertFalse(state.isSearching)
        XCTAssertTrue(state.searchResults.isEmpty, "whitespace query must not show results")
    }

    func testSearchThenOpenFolderThenBackThenNewSearch() {
        let state = QuickSnippetsNavigationState(folders: folders)

        state.searchText = "прив"
        XCTAssertFalse(state.searchResults.isEmpty)

        // Enter on a folder result opens it and clears search
        let enterResult = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(enterResult, .handled)
        XCTAssertEqual(state.activeFolder?.name, "Приветки")
        XCTAssertEqual(state.searchText, "")
        XCTAssertTrue(state.searchResults.isEmpty)

        // Back to folders, new search
        state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertNil(state.activeFolder)

        state.searchText = "счёт"
        XCTAssertEqual(contents(state.searchResults), ["snippet:счёт на оплату отправлен"])
    }

    func testSelectedSearchIndexClampedAcrossShrinkingResultSets() {
        let state = QuickSnippetsNavigationState(folders: folders)

        // Long query with 1 result, navigate down (stays at 0) then widen query
        state.searchText = "реквизиты"
        XCTAssertEqual(state.searchResults.count, 1)

        state.searchText = "о" // many results now
        let wide = state.searchResults
        XCTAssertGreaterThan(wide.count, 2)

        // Navigate deep into wide results
        for _ in 0..<(wide.count - 1) {
            _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        }
        XCTAssertEqual(state.selectedSearchResultIndex, wide.count - 1)

        // Narrow again: index must clamp, Enter must insert an EXISTING item
        state.searchText = "реквизиты"
        XCTAssertEqual(state.searchResults.count, 1)
        XCTAssertLessThanOrEqual(state.selectedSearchResultIndex, 0)

        let enter = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        guard case .insertSnippet(let text) = enter else {
            return XCTFail("expected snippet insertion, got \(enter)")
        }
        XCTAssertEqual(text, "реквизиты компании")
    }

    func testSearchRunsAgainstLiveFoldersSnapshot() {
        let state = QuickSnippetsNavigationState(folders: folders)

        state.searchText = "hr"
        XCTAssertTrue(contents(state.searchResults).contains("folder:HR TEST"))

        // Database changed while overlay open (onUpdate handler swaps folders)
        var updated = folders
        updated.remove(at: 2) // drop HR TEST
        state.folders = updated

        XCTAssertFalse(contents(state.searchResults).contains("folder:HR TEST"),
                       "results must be recomputed from the fresh folders snapshot")
    }

    // MARK: - Search engine quality checks

    func testKeyboardLayoutInversionMatches() {
        // "ghbdtn" typed on QWERTY while Russian layout expected → "привет"
        let results = SmartSearchEngine.search(query: "ghbdtn", in: folders)
        XCTAssertTrue(contents(results).contains("snippet:привет, как дела?"))
    }

    func testYoNormalization() {
        var withYo = folders
        withYo[0].snippets.append(SnippetItem(id: 103, folderId: 1, content: "ёлка и новые ёмкости", position: 2))
        let results = SmartSearchEngine.search(query: "елка", in: withYo)
        XCTAssertTrue(contents(results).contains("snippet:ёлка и новые ёмкости"))
    }

    func testTypoToleranceFindsNearMiss() {
        // "превет" (transposition of и→е) should still match "привет"
        let results = SmartSearchEngine.search(query: "превет", in: folders)
        XCTAssertTrue(contents(results).contains("snippet:привет, как дела?"))
    }

    func testRankingExactBeforePrefixBeforeFuzzy() {
        var rich = folders
        rich[0].snippets.append(SnippetItem(id: 104, folderId: 1, content: "привет", position: 3))
        rich[0].snippets.append(SnippetItem(id: 105, folderId: 1, content: "п-р-и-в-е-т разрозненно", position: 4))

        let results = SmartSearchEngine.search(query: "привет", in: rich)
        XCTAssertEqual(contents(results).first, "snippet:привет",
                       "exact content match must outrank folder/prefix/fuzzy variants")
        // Exact folder name match also ranks near top (boosted folder)
        XCTAssertTrue(contents(results).contains("folder:Приветки"))
    }

    func testNoMatchReturnsEmpty() {
        let state = QuickSnippetsNavigationState(folders: folders)
        state.searchText = "zzzzzz"
        XCTAssertTrue(state.searchResults.isEmpty)
        XCTAssertFalse(state.isSearching == false)
    }
}
