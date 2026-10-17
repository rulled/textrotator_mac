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

    // MARK: - 1. Root Level Folder Navigation (Down & Up)

    func testRootFolderNavigationDownAndUp() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertNil(state.activeFolder, "Overlay must open at root folders level")
        XCTAssertEqual(state.selectedFolderIndex, 0)
        XCTAssertEqual(state.selectedFolder?.name, "Клиентская поддержка")

        // Down: 0 -> 1
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 1)
        XCTAssertEqual(state.selectedFolder?.name, "Оплата и счета")

        // Down: 1 -> 2
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 2)
        XCTAssertEqual(state.selectedFolder?.name, "English Support")

        // Down at boundary: stays at 2
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 2)

        // Up: 2 -> 1
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 1)

        // Up: 1 -> 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 0)

        // Up at boundary: stays at 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 0)
    }

    // MARK: - 2. Open Folder via Enter and Right Arrow

    func testOpenFolderViaEnterAndRightArrow() {
        // Test opening via Right Arrow
        let state1 = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertNil(state1.activeFolder)

        var result = state1.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertNotNil(state1.activeFolder)
        XCTAssertEqual(state1.activeFolder?.name, "Клиентская поддержка")
        XCTAssertEqual(state1.selectedSnippetIndex, 0)

        // Test opening via Return key
        let state2 = QuickSnippetsNavigationState(folders: sampleFolders)
        _ = state2.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow) // select folder 1
        XCTAssertEqual(state2.selectedFolderIndex, 1)

        result = state2.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .handled)
        XCTAssertNotNil(state2.activeFolder)
        XCTAssertEqual(state2.activeFolder?.name, "Оплата и счета")
        XCTAssertEqual(state2.selectedSnippetIndex, 0)
    }

    // MARK: - 3. Snippet Navigation and Return Insertion

    func testSnippetNavigationAndInsertion() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        // Open first folder
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertNotNil(state.activeFolder)
        XCTAssertEqual(state.currentSnippets.count, 3)

        // Snippet navigation Down
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 1)

        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 2)

        // Boundary clamp
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 2)

        // Return inserts snippet 2
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .insertSnippet("Благодарим за обращение!"))
    }

    // MARK: - 4. Left Arrow Navigates Back to Folders Menu

    func testLeftArrowNavigatesBackToFolders() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        // Select folder 1
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(state.selectedFolderIndex, 1)

        // Open folder 1
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertNotNil(state.activeFolder)
        XCTAssertEqual(state.activeFolder?.name, "Оплата и счета")

        // Move to snippet 1
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(state.selectedSnippetIndex, 1)

        // Left Arrow returns back to Folders level
        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertNil(state.activeFolder, "Active folder must be cleared to return to root")
        XCTAssertEqual(state.selectedFolderIndex, 1, "Folder selection index must be preserved")

        // Left Arrow at root level is safely handled
        let rootLeft = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertEqual(rootLeft, .handled)
        XCTAssertNil(state.activeFolder)
    }

    // MARK: - 5. Tab Navigation

    func testTabCyclesFolders() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertNil(state.activeFolder)

        // At root level: Tab cycles folder selection
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyTab)
        XCTAssertEqual(state.selectedFolderIndex, 1)

        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyTab)
        XCTAssertEqual(state.selectedFolderIndex, 2)

        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyTab)
        XCTAssertEqual(state.selectedFolderIndex, 0)
    }

    // MARK: - 6. Escape Behavior

    func testEscapeBehavior() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // Empty search at root -> close overlay
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

    // MARK: - 7. Delete Behavior

    func testDeleteBehavior() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // Empty search: handled to suppress beep
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDelete), .handled)

        // Active search: ignored for text field
        state.searchText = "привет"
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDelete), .ignored)
    }

    // MARK: - 8. Search Results (Cached)

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
        XCTAssertEqual(state.activeFolder?.name, "English Support")
        XCTAssertFalse(state.isSearching, "Search text must be cleared on folder open")
    }

    // MARK: - 9. Empty Folders Safety

    func testEmptyFoldersSafety() {
        let state = QuickSnippetsNavigationState(folders: [])

        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape), .closeOverlay)
    }

    // MARK: - 10. Index Clamping on Folder Shrink

    func testFolderShrinkClampsIndices() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // Navigate to last folder
        state.selectFolder(index: 2)
        XCTAssertEqual(state.selectedFolderIndex, 2)
        XCTAssertEqual(state.selectedFolder?.name, "English Support")

        // Shrink to 2 folders -> index must clamp to 1
        state.folders = Array(sampleFolders.prefix(2))
        XCTAssertEqual(state.selectedFolderIndex, 1)
        XCTAssertEqual(state.selectedFolder?.name, "Оплата и счета")
    }

    // MARK: - 11. Zero-Snippet Folder

    func testZeroSnippetFolder() {
        let emptyFolder = FolderWithSnippets(id: 99, name: "Пустая", position: 0, snippets: [])
        let state = QuickSnippetsNavigationState(folders: [emptyFolder])

        // Open empty folder
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertNotNil(state.activeFolder)
        XCTAssertEqual(state.currentSnippets.count, 0)
        XCTAssertEqual(state.selectedSnippetIndex, 0)

        // Down arrow does nothing, doesn't crash
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow), .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 0)

        // Return on empty folder does nothing
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn), .handled)
    }

    // MARK: - 12. Search Result Index Clamp

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
