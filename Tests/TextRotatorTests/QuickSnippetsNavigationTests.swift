import XCTest
@testable import TextRotatorCore

@MainActor
final class QuickSnippetsNavigationTests: XCTestCase {

    private var sampleFolders: [FolderWithSnippets] {
        [
            FolderWithSnippets(
                id: 1,
                name: "Клиентская поддержка",
                position: 0,
                snippets: [
                    SnippetItem(id: 101, folderId: 1, content: "Здравствуйте! Чем могу помочь?", position: 0),
                    SnippetItem(id: 102, folderId: 1, content: "Уточните, пожалуйста, номер заказа.", position: 1),
                    SnippetItem(id: 103, folderId: 1, content: "Благодарим за обращение!", position: 2)
                ]
            ),
            FolderWithSnippets(
                id: 2,
                name: "Оплата и счета",
                position: 1,
                snippets: [
                    SnippetItem(id: 201, folderId: 2, content: "Гарантия возврата 100% средств.", position: 0),
                    SnippetItem(id: 202, folderId: 2, content: "Реквизиты для оплаты: ООО «Текст Ротатор»", position: 1)
                ]
            ),
            FolderWithSnippets(
                id: 3,
                name: "English Support",
                position: 2,
                snippets: [
                    SnippetItem(id: 301, folderId: 3, content: "Hello! How can I assist you today?", position: 0),
                    SnippetItem(id: 302, folderId: 3, content: "Thank you for reaching out!", position: 1)
                ]
            )
        ]
    }

    // MARK: - 1. Snippet Navigation (Down & Up)

    func testSnippetNavigationDownAndUp() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertEqual(state.selectedFolderIndex, 0)
        XCTAssertEqual(state.selectedSnippetIndex, 0)
        XCTAssertEqual(state.currentFolderSnippets.count, 3)

        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 1)

        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 2)

        // Boundary: stays at 2
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 2)

        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 1)

        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 0)

        // Boundary: stays at 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 0)
    }

    // MARK: - 2. Folder Switching (Right & Left)

    func testFolderSwitchingRightAndLeft() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertEqual(state.selectedFolderIndex, 0)
        XCTAssertEqual(state.currentFolder?.name, "Клиентская поддержка")

        // Move snippet index to verify reset on folder switch
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(state.selectedSnippetIndex, 1)

        // Right: folder 0 -> 1, snippet resets to 0
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 1)
        XCTAssertEqual(state.currentFolder?.name, "Оплата и счета")
        XCTAssertEqual(state.selectedSnippetIndex, 0)
        XCTAssertEqual(state.currentFolderSnippets.count, 2)

        // Right: folder 1 -> 2
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 2)
        XCTAssertEqual(state.currentFolder?.name, "English Support")

        // Right at boundary: stays at 2, no beep
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 2)

        // Left: 2 -> 1
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 1)

        // Left: 1 -> 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 0)

        // Left at boundary: stays at 0, no beep
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 0)
    }

    // MARK: - 3. Tab Cycles Folders

    func testTabCyclesFolders() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyTab)
        XCTAssertEqual(state.selectedFolderIndex, 1)

        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyTab)
        XCTAssertEqual(state.selectedFolderIndex, 2)

        // Wraps around
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyTab)
        XCTAssertEqual(state.selectedFolderIndex, 0)
    }

    // MARK: - 4. Return Inserts Snippet

    func testReturnKeyInsertsSelectedSnippet() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .insertSnippet("Здравствуйте! Чем могу помочь?"))

        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .insertSnippet("Уточните, пожалуйста, номер заказа."))

        // Switch folder and return
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .insertSnippet("Гарантия возврата 100% средств."))
    }

    // MARK: - 5. Escape: Clear Search vs Close

    func testEscapeBehavior() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // Empty search -> close overlay
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape), .closeOverlay)

        // Active search -> clear search
        state.searchText = "заказ"
        XCTAssertTrue(state.isSearching)

        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.searchText, "")
        XCTAssertFalse(state.isSearching)

        // Second escape -> close overlay
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape)
        XCTAssertEqual(result, .closeOverlay)
    }

    // MARK: - 6. Delete Behavior

    func testDeleteBehavior() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // Empty search: handled to suppress beep
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDelete), .handled)

        // Active search: ignored for text field
        state.searchText = "привет"
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDelete), .ignored)
    }

    // MARK: - 7. Search Results (Cached)

    func testSearchResultsAreCached() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // Empty search -> empty results
        XCTAssertTrue(state.searchResults.isEmpty)

        // Search -> results populated
        state.searchText = "возврат"
        XCTAssertFalse(state.searchResults.isEmpty)

        // Results stable across accesses (same stored array)
        let r1 = state.searchResults
        let r2 = state.searchResults
        XCTAssertEqual(r1.count, r2.count)

        // Down arrow in search
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)

        // Return inserts
        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        if case .insertSnippet(let content) = result {
            XCTAssertTrue(content.contains("возврат"))
        } else {
            XCTFail("Expected .insertSnippet")
        }
    }

    func testSearchFolderResultOpensFolder() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.searchText = "english"

        let folderIdx = state.searchResults.firstIndex {
            if case .folder(let f, _) = $0, f.name == "English Support" { return true }
            return false
        }
        XCTAssertNotNil(folderIdx)

        // Navigate to folder result and press Return
        for _ in 0..<(folderIdx ?? 0) {
            _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        }
        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.currentFolder?.name, "English Support")
        XCTAssertFalse(state.isSearching, "Search text must be cleared on folder open")
    }

    // MARK: - 8. Empty Folders Safety

    func testEmptyFoldersSafety() {
        let state = QuickSnippetsNavigationState(folders: [])

        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape), .closeOverlay)
    }

    // MARK: - 9. Index Clamping on Folder Shrink

    func testFolderShrinkClampsIndices() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // Navigate to last folder
        state.selectFolder(index: 2)
        XCTAssertEqual(state.selectedFolderIndex, 2)
        XCTAssertEqual(state.currentFolder?.name, "English Support")

        // Shrink to 2 folders -> index must clamp to 1
        state.folders = Array(sampleFolders.prefix(2))
        XCTAssertEqual(state.selectedFolderIndex, 1)
        XCTAssertEqual(state.currentFolder?.name, "Оплата и счета")
    }

    func testSnippetIndexClampsOnFolderSwitch() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // Navigate to snippet 2 in folder 0 (3 snippets)
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(state.selectedSnippetIndex, 2)

        // Switch to folder 1 (2 snippets) -> snippet resets to 0
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertEqual(state.selectedFolderIndex, 1)
        XCTAssertEqual(state.selectedSnippetIndex, 0)
    }

    // MARK: - 10. Zero-Snippet Folder

    func testZeroSnippetFolder() {
        let emptyFolder = FolderWithSnippets(id: 99, name: "Пустая", position: 0, snippets: [])
        let state = QuickSnippetsNavigationState(folders: [emptyFolder])

        XCTAssertEqual(state.currentFolderSnippets.count, 0)
        XCTAssertEqual(state.selectedSnippetIndex, 0)

        // Down arrow does nothing, doesn't crash
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow), .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 0)

        // Return on empty folder does nothing
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn), .handled)
    }

    // MARK: - 11. Search Result Index Clamp

    func testSearchResultIndexClampsOnTextChange() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.searchText = "100%"
        XCTAssertFalse(state.searchResults.isEmpty)

        // Navigate deep
        for _ in 0..<10 {
            _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        }

        // Change search to something with fewer results
        state.searchText = "zzzzzzzz"
        XCTAssertTrue(state.searchResults.isEmpty)
        XCTAssertEqual(state.selectedSearchResultIndex, 0, "Index must clamp to 0 on empty results")
    }
}
