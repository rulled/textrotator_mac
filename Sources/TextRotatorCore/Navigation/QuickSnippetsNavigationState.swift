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
@MainActor
public final class QuickSnippetsNavigationState: ObservableObject {

    // MARK: - State Properties

    /// Active folder if user drilled down into a specific folder; nil means root/unified level.
    @Published public var activeFolder: FolderWithSnippets? = nil

    /// Selection index among root folders.
    @Published public var selectedFolderIndex: Int = 0

    /// Selection index among snippets inside an active folder.
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

    /// Available folders with their snippets.
    public var folders: [FolderWithSnippets] = []

    // MARK: - Initializer

    public init(folders: [FolderWithSnippets] = []) {
        self.folders = folders
    }

    // MARK: - Computed Properties

    public var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var searchResults: [SmartSearchItem] {
        SmartSearchEngine.search(query: searchText, in: folders)
    }

    public var displayedFolderSnippets: [SnippetItem] {
        guard let folder = activeFolder else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return folder.snippets
        }
        return folder.snippets.filter { snippet in
            SmartSearchEngine.calculateScore(query: query, candidate: snippet.content) > 0
        }
    }

    // MARK: - Navigation Transitions

    public func openFolder(_ folder: FolderWithSnippets) {
        activeFolder = folder
        selectedSnippetIndex = 0
        searchText = ""
    }

    public func backToRoot() {
        activeFolder = nil
        selectedFolderIndex = 0
        selectedSearchResultIndex = 0
        searchText = ""
    }

    // MARK: - Standard Key Codes

    public static let keyLeftArrow: UInt16 = 123
    public static let keyRightArrow: UInt16 = 124
    public static let keyDownArrow: UInt16 = 125
    public static let keyUpArrow: UInt16 = 126
    public static let keyReturn: UInt16 = 36
    public static let keyEscape: UInt16 = 53
    public static let keyDelete: UInt16 = 51

    // MARK: - Key Event Processing

    /// Evaluates a key code and transitions state accordingly.
    /// - Parameter keyCode: Hardware virtual key code.
    /// - Returns: `QuickSnippetsKeyResult` indicating whether it was handled, ignored, or triggers an action.
    public func handleKeyDown(keyCode: UInt16) -> QuickSnippetsKeyResult {
        // 1. DOWN ARROW (125)
        if keyCode == Self.keyDownArrow {
            if activeFolder != nil {
                if !displayedFolderSnippets.isEmpty && selectedSnippetIndex < displayedFolderSnippets.count - 1 {
                    selectedSnippetIndex += 1
                }
            } else if isSearching {
                if !searchResults.isEmpty && selectedSearchResultIndex < searchResults.count - 1 {
                    selectedSearchResultIndex += 1
                }
            } else {
                if !folders.isEmpty && selectedFolderIndex < folders.count - 1 {
                    selectedFolderIndex += 1
                }
            }
            return .handled
        }

        // 2. UP ARROW (126)
        if keyCode == Self.keyUpArrow {
            if activeFolder != nil {
                if selectedSnippetIndex > 0 {
                    selectedSnippetIndex -= 1
                }
            } else if isSearching {
                if selectedSearchResultIndex > 0 {
                    selectedSearchResultIndex -= 1
                }
            } else {
                if selectedFolderIndex > 0 {
                    selectedFolderIndex -= 1
                }
            }
            return .handled
        }

        // 3. RIGHT ARROW (124)
        if keyCode == Self.keyRightArrow {
            if activeFolder == nil && !isSearching {
                if !folders.isEmpty {
                    let idx = max(0, min(selectedFolderIndex, folders.count - 1))
                    openFolder(folders[idx])
                    return .handled
                }
            } else if activeFolder == nil && isSearching {
                if !searchResults.isEmpty {
                    let idx = max(0, min(selectedSearchResultIndex, searchResults.count - 1))
                    if case .folder(let folder, _) = searchResults[idx] {
                        openFolder(folder)
                        return .handled
                    }
                }
            }
            return .ignored
        }

        // 4. LEFT ARROW (123)
        if keyCode == Self.keyLeftArrow {
            if activeFolder != nil {
                backToRoot()
                return .handled
            }
            return .ignored
        }

        // 5. ESCAPE (53)
        if keyCode == Self.keyEscape {
            if activeFolder != nil {
                backToRoot()
                return .handled
            }
            if !searchText.isEmpty {
                searchText = ""
                selectedSearchResultIndex = 0
                return .handled
            }
            return .closeOverlay
        }

        // 6. RETURN / ENTER (36)
        if keyCode == Self.keyReturn {
            if activeFolder != nil {
                if !displayedFolderSnippets.isEmpty {
                    let idx = max(0, min(selectedSnippetIndex, displayedFolderSnippets.count - 1))
                    return .insertSnippet(displayedFolderSnippets[idx].content)
                }
                return .handled
            }
            if isSearching {
                if !searchResults.isEmpty {
                    let idx = max(0, min(selectedSearchResultIndex, searchResults.count - 1))
                    let item = searchResults[idx]
                    switch item {
                    case .folder(let folder, _):
                        openFolder(folder)
                        return .handled
                    case .snippet(let snippet, _, _, _):
                        return .insertSnippet(snippet.content)
                    }
                }
                return .handled
            }
            if !folders.isEmpty {
                let idx = max(0, min(selectedFolderIndex, folders.count - 1))
                openFolder(folders[idx])
                return .handled
            }
            return .handled
        }

        // 7. BACKSPACE / DELETE (51)
        if keyCode == Self.keyDelete {
            if searchText.isEmpty && activeFolder != nil {
                backToRoot()
                return .handled
            }
            return .ignored
        }

        return .ignored
    }
}
