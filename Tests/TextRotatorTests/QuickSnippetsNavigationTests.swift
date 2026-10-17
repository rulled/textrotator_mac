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
    // MARK: - 1. Root Folders Navigation (Down, Up)

    func testRootNavigationDownAndUp() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertNil(state.activeFolder)
        XCTAssertEqual(state.selectedFolderIndex, 0)

        // Down Arrow: moves 0 -> 1
        var result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 1)

        // Down Arrow: moves 1 -> 2
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 2)

        // Down Arrow at boundary: stays at 2 (cannot exceed count - 1)
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 2)

        // Up Arrow: moves 2 -> 1
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 1)

        // Up Arrow: moves 1 -> 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 0)

        // Up Arrow at boundary: stays at 0
        result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.selectedFolderIndex, 0)
    }

    // MARK: - 2. Root Entry into Folder (Right Arrow & Return)

    func testRootRightArrowEntersFolder() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.selectedFolderIndex = 1 // "Оплата и счета"

        // Right Arrow enters folder
        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow)
        XCTAssertEqual(result, .handled)
        XCTAssertNotNil(state.activeFolder)
        XCTAssertEqual(state.activeFolder?.name, "Оплата и счета")
        XCTAssertEqual(state.selectedSnippetIndex, 0)
        XCTAssertEqual(state.searchText, "")
    }

    func testRootReturnEntersFolder() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.selectedFolderIndex = 2 // "English Support"

        // Return enters folder
        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .handled)
        XCTAssertNotNil(state.activeFolder)
        XCTAssertEqual(state.activeFolder?.name, "English Support")
        XCTAssertEqual(state.selectedSnippetIndex, 0)
    }

    // MARK: - 3. Inside Folder Navigation (Down, Up)

    func testInsideFolderNavigationDownAndUp() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.openFolder(sampleFolders[0]) // 3 snippets: 101, 102, 103

        XCTAssertEqual(state.selectedSnippetIndex, 0)

        // Down Arrow: 0 -> 1
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(state.selectedSnippetIndex, 1)

        // Down Arrow: 1 -> 2
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(state.selectedSnippetIndex, 2)

        // Down Arrow at boundary: stays at 2
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow)
        XCTAssertEqual(state.selectedSnippetIndex, 2)

        // Up Arrow: 2 -> 1
        _ = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow)
        XCTAssertEqual(state.selectedSnippetIndex, 1)
    }

    // MARK: - 4. CRUCIAL: Inside Folder Left Arrow Returns to Root (NO BEEP)

    func testInsideFolderLeftArrowReturnsToRoot() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.openFolder(sampleFolders[1]) // "Оплата и счета"
        state.selectedSnippetIndex = 1

        XCTAssertNotNil(state.activeFolder)

        // Left Arrow (123) MUST return .handled and reset activeFolder to nil!
        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow)
        XCTAssertEqual(result, .handled, "Left arrow inside folder must be handled without beeping")
        XCTAssertNil(state.activeFolder, "Active folder must be reset to nil")
        XCTAssertEqual(state.selectedFolderIndex, 0)
        XCTAssertEqual(state.searchText, "")
    }

    // MARK: - 5. Inside Folder Escape Returns to Root

    func testInsideFolderEscapeReturnsToRoot() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.openFolder(sampleFolders[0])

        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape)
        XCTAssertEqual(result, .handled)
        XCTAssertNil(state.activeFolder)
    }

    // MARK: - 6. Inside Folder Backspace / Delete Returns to Root (When Search Empty)

    func testInsideFolderBackspaceWhenEmptyReturnsToRoot() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.openFolder(sampleFolders[0])
        state.searchText = ""

        // Delete (51) when search is empty returns to root
        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDelete)
        XCTAssertEqual(result, .handled)
        XCTAssertNil(state.activeFolder)
    }

    func testInsideFolderBackspaceWhenTypingIsIgnoredForTextField() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.openFolder(sampleFolders[0])
        state.searchText = "но"

        // When search is not empty, Backspace must be ignored so TextField deletes character
        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDelete)
        XCTAssertEqual(result, .ignored)
        XCTAssertNotNil(state.activeFolder)
    }

    // MARK: - 7. Inside Folder Return Inserts Selected Snippet

    func testInsideFolderReturnInsertsSnippet() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.openFolder(sampleFolders[0])
        state.selectedSnippetIndex = 1 // "Уточните, пожалуйста, номер заказа."

        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .insertSnippet("Уточните, пожалуйста, номер заказа."))
    }

    // MARK: - 8. Unified Search Navigation & Instant Insertion

    func testUnifiedSearchNavigationAndInsertion() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.searchText = "возврат"

        XCTAssertTrue(state.isSearching)
        XCTAssertFalse(state.searchResults.isEmpty)

        // Find the snippet result in search results
        let firstResult = state.searchResults[0]
        if case .snippet(let s, _, _, _) = firstResult {
            XCTAssertTrue(s.content.contains("100%"))
        }

        // Return on snippet inserts text immediately
        let returnResult = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        if case .insertSnippet(let content) = returnResult {
            XCTAssertTrue(content.contains("возврат"))
        } else {
            XCTFail("Expected .insertSnippet result on snippet return")
        }
    }

    func testUnifiedSearchFolderResultEntry() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.searchText = "english"

        XCTAssertTrue(state.isSearching)
        XCTAssertFalse(state.searchResults.isEmpty)

        // The folder "English Support" matches with high score
        var foundFolderIndex: Int?
        for (i, item) in state.searchResults.enumerated() {
            if case .folder(let f, _) = item, f.name == "English Support" {
                foundFolderIndex = i
                break
            }
        }
        XCTAssertNotNil(foundFolderIndex)

        state.selectedSearchResultIndex = foundFolderIndex!

        // Pressing Return on folder drills down into that folder
        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn)
        XCTAssertEqual(result, .handled)
        XCTAssertNotNil(state.activeFolder)
        XCTAssertEqual(state.activeFolder?.name, "English Support")
    }

    func testUnifiedSearchEscapeClearsSearch() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        state.searchText = "запрос"

        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape)
        XCTAssertEqual(result, .handled)
        XCTAssertEqual(state.searchText, "")
        XCTAssertFalse(state.isSearching)
        XCTAssertNil(state.activeFolder)
    }

    // MARK: - 9. Root Escape Closes Overlay

    func testRootEscapeClosesOverlay() {
        let state = QuickSnippetsNavigationState(folders: sampleFolders)
        XCTAssertNil(state.activeFolder)
        XCTAssertEqual(state.searchText, "")

        let result = state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyEscape)
        XCTAssertEqual(result, .closeOverlay)
    }

    // MARK: - 10. Empty Folders Safety

    func testEmptyFoldersSafety() {
        let state = QuickSnippetsNavigationState(folders: [])

        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyDownArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyUpArrow), .handled)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyRightArrow), .ignored)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyLeftArrow), .ignored)
        XCTAssertEqual(state.handleKeyDown(keyCode: QuickSnippetsNavigationState.keyReturn), .handled)
    }
}
