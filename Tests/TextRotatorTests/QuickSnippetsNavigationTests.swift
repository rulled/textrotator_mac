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

    // MARK: - 1. Snippet Selection Navigation (Down & Up Arrows)

    func testSnippetNavigationDownAndUp() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertEqual(state.selectedFolderIndex, 0)
        XCTAssertEqual(state.selectedSnippetIndex, 0)
        XCTAssertEqual(state.currentFolderSnippets.count, 3)

        // Down Arrow: moves 0 -> 1
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 1)

        // Down Arrow: moves 1 -> 2
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 2)

        // Down Arrow at boundary: stays at 2 (cannot exceed count - 1)
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 2)

        // Up Arrow: moves 2 -> 1
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 1)

        // Up Arrow: moves 1 -> 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 0)

        // Up Arrow at boundary: stays at 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedSnippetIndex, 0)
    }

    // MARK: - 2. Folder Switching (Right & Left Arrows)

    func testFolderSwitchingRightAndLeft() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertEqual(state.selectedFolderIndex, 0)
        XCTAssertEqual(state.currentFolder?.name, "Клиентская поддержка")

        // Move snippet index to 1 in folder 0
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(state.selectedSnippetIndex, 1)

        // Right Arrow: switches to folder 1 ("Оплата и счета") and resets snippet index to 0
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 1)
        XCTAssertEqual(state.currentFolder?.name, "Оплата и счета")
        XCTAssertEqual(state.selectedSnippetIndex, 0)
        XCTAssertEqual(state.currentFolderSnippets.count, 2)

        // Right Arrow: switches to folder 2 ("English Support")
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 2)
        XCTAssertEqual(state.currentFolder?.name, "English Support")

        // Right Arrow at boundary: stays at 2 and is handled without beeping
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 2)

        // Left Arrow: switches back to folder 1
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 1)
        XCTAssertEqual(state.currentFolder?.name, "Оплата и счета")

        // Left Arrow: switches back to folder 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 0)

        // Left Arrow at boundary: stays at 0 and is handled without beeping
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 0)
    }

    // MARK: - 3. Folder Cycling (Tab Key)

    func testTabCyclesFolders() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertEqual(state.selectedFolderIndex, 0)

        // Tab: 0 -> 1
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyTab)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 1)

        // Tab: 1 -> 2
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyTab)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 2)

        // Tab at end wraps around: 2 -> 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyTab)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 0)
    }

    // MARK: - 4. Snippet Insertion on Return Key

    func testReturnKeyInsertsSelectedSnippet() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertEqual(state.selectedSnippetIndex, 0)

        // Return on first snippet in folder 0
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .insertSnippet("Здравствуйте! Чем могу помочь?"))

        // Move to snippet 1 and press Return
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .insertSnippet("Уточните, пожалуйста, номер заказа."))

        // Switch to folder 1 and press Return on first snippet
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .insertSnippet("Гарантия возврата 100% средств."))
    }

    // MARK: - 5. Escape Behavior (Clear Search vs Close Overlay)

    func testEscapeBehavior() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // When search is empty: Escape closes overlay
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape)
        XCTAssertEqual(result, .closeOverlay)

        // When searching: Escape clears search text and stays open
        state.searchText = "заказ"
        XCTAssertTrue(state.isSearching)

        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.searchText, "")
        XCTAssertFalse(state.isSearching)

        // Second Escape closes overlay
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape)
        XCTAssertEqual(result, .closeOverlay)
    }

    // MARK: - 6. Backspace / Delete Behavior

    func testDeleteBehavior() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)

        // When search is empty, Delete is handled to suppress system beep
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDelete)
        XCTAssertEqual(result, .handled)

        // When typing in search, Delete is ignored so TextField processes character deletion
        state.searchText = "привет"
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDelete)
        XCTAssertEqual(result, .ignored)
    }

    // MARK: - 7. Unified Search Navigation & Insertion

    func testUnifiedSearchNavigationAndInsertion() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.searchText = "возврат"

        XCTAssertTrue(state.isSearching)
        XCTAssertFalse(state.searchResults.isEmpty)

        // Down arrow in search results
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)

        // Return on search result inserts snippet
        let returnResult = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        if case .insertSnippet(let content) = returnResult {
            XCTAssertTrue(content.contains("возврат"))
        } else {
            XCTFail("Expected .insertSnippet result on search return")
        }
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
}
