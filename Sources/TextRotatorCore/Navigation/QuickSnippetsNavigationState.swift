import Foundation
import Combine

/// Outcome of processing a keyboard event in the QuickSnippets state machine.
public enum QuickSnippetsKeyResult: Equatable, Sendable {
    case handled
    case ignored
    case insertSnippet(String)
    case closeOverlay
}

/// Decoupled, fully unit-testable navigation state machine for QuickSnippets overlay.
///
/// Implements instant tabbed folder + snippet navigation:
/// - `↓` / `↑` (Down/Up): Move selection through snippets in the active folder (or search results).
/// - `→` / `←` (Right/Left) or `Tab`: Switch active folder tabs, instantly updating visible snippets.
/// - `Enter`: Insert selected snippet at cursor in the background target application.
/// - `Escape`: Clear search query if active, or dismiss overlay.
@MainActor
public final class QuickSnippetsNavigationState: ObservableObject {

    // MARK: - State Properties

    /// Available folders with their snippets.
    @Published public var folders: [FolderWithSnippets] = [] {
        didSet {
            clampIndices()
        }
    }

    /// Selection index among folder tabs.
    @Published public var selectedFolderIndex: Int = 0 {
        didSet {
            if oldValue != selectedFolderIndex {
                clampIndices()
            }
        }
    }

    /// Selection index among snippets inside the currently selected folder.
    @Published public var selectedSnippetIndex: Int = 0

    /// Selection index among unified search results.
    @Published public var selectedSearchResultIndex: Int = 0

    /// Current search query in the unified search bar.
    @Published public var searchText: String = "" {
        didSet {
            selectedSearchResultIndex = 0
            selectedSnippetIndex = 0
        }
    }

    // MARK: - Initializer

    public init(folders: [FolderWithSnippets] = []) {
        self.folders = folders
        self.selectedFolderIndex = 0
        self.selectedSnippetIndex = 0
        self.selectedSearchResultIndex = 0
    }

    // MARK: - Computed Properties

    public var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The currently active folder selected via folder tabs.
    public var currentFolder: FolderWithSnippets? {
        guard !folders.isEmpty else { return nil }
        let idx = max(0, min(selectedFolderIndex, folders.count - 1))
        return folders[idx]
    }

    /// Backward-compatibility alias for currentFolder.
    public var activeFolder: FolderWithSnippets? {
        currentFolder
    }

    /// Snippets belonging to the currently selected folder.
    public var currentFolderSnippets: [SnippetItem] {
        guard let folder = currentFolder else { return [] }
        return folder.snippets
    }

    /// Backward-compatibility alias for currentFolderSnippets.
    public var displayedFolderSnippets: [SnippetItem] {
        currentFolderSnippets
    }

    /// Unified search results matching `searchText`.
    public var searchResults: [SmartSearchItem] {
        SmartSearchEngine.search(query: searchText, in: folders)
    }

    // MARK: - Navigation Transitions

    public func selectFolder(index: Int) {
        guard !folders.isEmpty else { return }
        selectedFolderIndex = max(0, min(index, folders.count - 1))
        selectedSnippetIndex = 0
        searchText = ""
    }

    public func openFolder(_ folder: FolderWithSnippets) {
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            selectFolder(index: idx)
        }
    }

    public func backToRoot() {
        selectedFolderIndex = 0
        selectedSnippetIndex = 0
        selectedSearchResultIndex = 0
        searchText = ""
    }

    private func clampIndices() {
        if !folders.isEmpty {
            let maxFolder = folders.count - 1
            if selectedFolderIndex > maxFolder {
                selectedFolderIndex = maxFolder
            } else if selectedFolderIndex < 0 {
                selectedFolderIndex = 0
            }

            let snippetCount = currentFolderSnippets.count
            if snippetCount > 0 {
                if selectedSnippetIndex >= snippetCount {
                    selectedSnippetIndex = snippetCount - 1
                } else if selectedSnippetIndex < 0 {
                    selectedSnippetIndex = 0
                }
            } else if selectedSnippetIndex != 0 {
                selectedSnippetIndex = 0
            }
        } else {
            if selectedFolderIndex != 0 {
                selectedFolderIndex = 0
            }
            if selectedSnippetIndex != 0 {
                selectedSnippetIndex = 0
            }
        }
    }

    // MARK: - Standard Key Codes

    public static let keyLeftArrow: UInt16 = 123
    public static let keyRightArrow: UInt16 = 124
    public static let keyDownArrow: UInt16 = 125
    public static let keyUpArrow: UInt16 = 126
    public static let keyTab: UInt16 = 48
    public static let keyReturn: UInt16 = 36
    public static let keyEscape: UInt16 = 53
    public static let keyDelete: UInt16 = 51
    // MARK: - Key Event Processing

    /// Evaluates a key code and transitions state accordingly.
    /// - Parameter keyCode: Hardware virtual key code.
    /// - Returns: `QuickSnippetsKeyResult` indicating whether it was handled, ignored, or triggers an action.
    public func handleKeyDown(keyCode: UInt16) -> QuickSnippetsKeyResult {
        // 1. DOWN ARROW (125) - Navigate content downwards
        if keyCode == Self.keyDownArrow {
            if isSearching {
                if !searchResults.isEmpty && selectedSearchResultIndex < searchResults.count - 1 {
                    selectedSearchResultIndex += 1
                }
            } else {
                let count = currentFolderSnippets.count
                if count > 0 && selectedSnippetIndex < count - 1 {
                    selectedSnippetIndex += 1
                }
            }
            return .handled
        }

        // 2. UP ARROW (126) - Navigate content upwards
        if keyCode == Self.keyUpArrow {
            if isSearching {
                if selectedSearchResultIndex > 0 {
                    selectedSearchResultIndex -= 1
                }
            } else {
                if selectedSnippetIndex > 0 {
                    selectedSnippetIndex -= 1
                }
            }
            return .handled
        }

        // 3. RIGHT ARROW (124) - Switch folder tab to the right (when not typing in search)
        if keyCode == Self.keyRightArrow {
            if !isSearching {
                if !folders.isEmpty && selectedFolderIndex < folders.count - 1 {
                    selectedFolderIndex += 1
                    selectedSnippetIndex = 0
                    return .handled
                }
                return .handled // Consume to prevent system beep at boundary
            }
            // When searching, let the arrow navigate cursor in search text field
            return .ignored
        }

        // 4. LEFT ARROW (123) - Switch folder tab to the left (when not typing in search)
        if keyCode == Self.keyLeftArrow {
            if !isSearching {
                if !folders.isEmpty && selectedFolderIndex > 0 {
                    selectedFolderIndex -= 1
                    selectedSnippetIndex = 0
                    return .handled
                }
                return .handled // Consume to prevent system beep at boundary
            }
            // When searching, let the arrow navigate cursor in search text field
            return .ignored
        }

        // 5. TAB (48) - Cycle to next folder tab
        if keyCode == Self.keyTab {
            if !isSearching && !folders.isEmpty {
                selectedFolderIndex = (selectedFolderIndex + 1) % folders.count
                selectedSnippetIndex = 0
                return .handled
            }
            return .ignored
        }

        // 6. RETURN / ENTER (36) - Insert snippet or enter folder
        if keyCode == Self.keyReturn {
            if isSearching {
                guard !searchResults.isEmpty else { return .handled }
                let idx = max(0, min(selectedSearchResultIndex, searchResults.count - 1))
                let item = searchResults[idx]
                switch item {
                case .snippet(let snippet, _, _, _):
                    return .insertSnippet(snippet.content)
                case .folder(let folder, _):
                    openFolder(folder)
                    return .handled
                }
            } else {
                let snippets = currentFolderSnippets
                guard !snippets.isEmpty else { return .handled }
                let idx = max(0, min(selectedSnippetIndex, snippets.count - 1))
                let snippet = snippets[idx]
                return .insertSnippet(snippet.content)
            }
        }

        // 7. ESCAPE (53) - Clear search or dismiss overlay
        if keyCode == Self.keyEscape {
            if isSearching {
                searchText = ""
                return .handled
            }
            return .closeOverlay
        }

        // 8. BACKSPACE / DELETE (51)
        if keyCode == Self.keyDelete {
            if isSearching && !searchText.isEmpty {
                return .ignored // Let text field delete characters
            }
            // Prevent beep on backspace when text field is empty
            return .handled
        }

        // All other keys (letters, digits, punctuation, spaces) pass through to TextField
        return .ignored
    }
}
