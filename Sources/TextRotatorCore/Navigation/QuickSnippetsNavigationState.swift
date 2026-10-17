import Foundation
import Combine

/// Outcome of processing a keyboard event in the QuickSnippets state machine.
public enum QuickSnippetsKeyResult: Equatable, Sendable {
    case handled
    case ignored
    case insertSnippet(String)
    case closeOverlay
}

/// Decoupled, fully unit-testable navigation state machine for QuickSnippets overlay (Lite Mode).
///
/// Hierarchical 2-level UX:
/// - Level 1 (activeFolder == nil): List of FOLDERS.
///   - `↓` / `↑`: Select folder.
///   - `→` / `↵`: Open selected folder.
///   - `esc`: Close overlay.
/// - Level 2 (activeFolder != nil): List of SNIPPETS in opened folder.
///   - `↓` / `↑`: Select snippet.
///   - `↵`: Insert selected snippet.
///   - `←`: Back to folders list.
///   - `esc`: Close overlay.
/// - Search mode (searchText != ""): Unified fuzzy search across all folders and snippets.
///   - `↓` / `↑`: Navigate search results.
///   - `↵`: Insert snippet or open folder.
///   - `esc`: Clear search.
@MainActor
public final class QuickSnippetsNavigationState: ObservableObject {

    // MARK: - Published State

    @Published public var folders: [FolderWithSnippets] = [] {
        didSet { rebuildState() }
    }

    @Published public var searchText: String = "" {
        didSet { rebuildState() }
    }

    @Published public private(set) var activeFolder: FolderWithSnippets?
    @Published public private(set) var selectedFolderIndex: Int = 0
    @Published public private(set) var selectedSnippetIndex: Int = 0
    @Published public private(set) var selectedSearchResultIndex: Int = 0
    @Published public private(set) var searchResults: [SmartSearchItem] = []

    // MARK: - Computed

    public var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var selectedFolder: FolderWithSnippets? {
        guard !folders.isEmpty, folders.indices.contains(selectedFolderIndex) else { return nil }
        return folders[selectedFolderIndex]
    }

    public var currentFolder: FolderWithSnippets? {
        if let activeFolder { return activeFolder }
        return selectedFolder
    }

    public var currentSnippets: [SnippetItem] {
        activeFolder?.snippets ?? []
    }

    public var currentFolderSnippets: [SnippetItem] {
        currentFolder?.snippets ?? []
    }

    // MARK: - Init

    public init(folders: [FolderWithSnippets] = [], activeFolder: FolderWithSnippets? = nil) {
        self.folders = folders
        self.activeFolder = activeFolder
        rebuildState()
    }

    // MARK: - State Rebuild (single point of truth)

    private func rebuildState() {
        // Clamp folder index
        if folders.isEmpty {
            selectedFolderIndex = 0
            selectedSnippetIndex = 0
            activeFolder = nil
        } else {
            let maxFolder = folders.count - 1
            if selectedFolderIndex > maxFolder {
                selectedFolderIndex = maxFolder
            }

            // Sync activeFolder with updated folders list
            if let current = activeFolder {
                if let updated = folders.first(where: { $0.id == current.id }) {
                    activeFolder = updated
                    let count = updated.snippets.count
                    if count == 0 {
                        selectedSnippetIndex = 0
                    } else if selectedSnippetIndex >= count {
                        selectedSnippetIndex = count - 1
                    }
                } else {
                    activeFolder = nil
                    selectedSnippetIndex = 0
                }
            } else {
                selectedSnippetIndex = 0
            }
        }

        // Recompute search results
        let newResults = isSearching
            ? SmartSearchEngine.search(query: searchText, in: folders)
            : []
        searchResults = newResults

        // Clamp search result index
        if searchResults.isEmpty {
            selectedSearchResultIndex = 0
        } else if selectedSearchResultIndex >= searchResults.count {
            selectedSearchResultIndex = searchResults.count - 1
        }
    }

    // MARK: - Navigation API

    public func selectFolder(index: Int) {
        guard !folders.isEmpty else { return }
        selectedFolderIndex = max(0, min(index, folders.count - 1))
    }

    public func selectSnippet(index: Int) {
        let maxIdx = max(0, currentSnippets.count - 1)
        selectedSnippetIndex = max(0, min(index, maxIdx))
    }

    public func openFolder(_ folder: FolderWithSnippets) {
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            selectedFolderIndex = idx
            activeFolder = folders[idx]
        } else {
            activeFolder = folder
        }
        selectedSnippetIndex = 0
        if isSearching { searchText = "" }
    }

    public func openSelectedFolder() {
        guard let folder = selectedFolder else { return }
        openFolder(folder)
    }

    public func backToFolders() {
        activeFolder = nil
        selectedSnippetIndex = 0
        if isSearching { searchText = "" }
    }

    public func backToRoot() {
        activeFolder = nil
        selectedFolderIndex = 0
        selectedSnippetIndex = 0
        selectedSearchResultIndex = 0
        if !searchText.isEmpty { searchText = "" }
    }

    // MARK: - Key Codes

    public static let keyLeftArrow: UInt16 = 123
    public static let keyRightArrow: UInt16 = 124
    public static let keyDownArrow: UInt16 = 125
    public static let keyUpArrow: UInt16 = 126
    public static let keyTab: UInt16 = 48
    public static let keyReturn: UInt16 = 36
    public static let keyEscape: UInt16 = 53
    public static let keyDelete: UInt16 = 51

    // MARK: - Key Event Processing

    public func handleKeyDown(keyCode: UInt16) -> QuickSnippetsKeyResult {
        switch keyCode {

        // ↓ Down Arrow
        case Self.keyDownArrow:
            if isSearching {
                if selectedSearchResultIndex < searchResults.count - 1 {
                    selectedSearchResultIndex += 1
                }
            } else if activeFolder == nil {
                // Navigate folders down
                if selectedFolderIndex < folders.count - 1 {
                    selectedFolderIndex += 1
                }
            } else {
                // Navigate snippets down
                if selectedSnippetIndex < currentSnippets.count - 1 {
                    selectedSnippetIndex += 1
                }
            }
            return .handled

        // ↑ Up Arrow
        case Self.keyUpArrow:
            if isSearching {
                if selectedSearchResultIndex > 0 {
                    selectedSearchResultIndex -= 1
                }
            } else if activeFolder == nil {
                // Navigate folders up
                if selectedFolderIndex > 0 {
                    selectedFolderIndex -= 1
                }
            } else {
                // Navigate snippets up
                if selectedSnippetIndex > 0 {
                    selectedSnippetIndex -= 1
                }
            }
            return .handled

        // → Right Arrow — Open folder if at root level
        case Self.keyRightArrow:
            if isSearching {
                guard !searchResults.isEmpty else { return .ignored }
                let idx = min(selectedSearchResultIndex, searchResults.count - 1)
                if case .folder(let folder, _) = searchResults[idx] {
                    openFolder(folder)
                    return .handled
                }
                return .ignored
            } else if activeFolder == nil {
                openSelectedFolder()
                return .handled
            } else {
                // Inside folder: right arrow has no deeper level
                return .handled
            }

        // ← Left Arrow — Go back to folders if inside folder
        case Self.keyLeftArrow:
            if isSearching {
                return .ignored
            } else if activeFolder != nil {
                backToFolders()
                return .handled
            } else {
                // Already at root level
                return .handled
            }

        // ⇥ Tab — cycle through folders if at root level
        case Self.keyTab:
            guard !isSearching, !folders.isEmpty else { return .ignored }
            if activeFolder == nil {
                selectedFolderIndex = (selectedFolderIndex + 1) % folders.count
                return .handled
            } else {
                // Inside folder, tab switches to next folder directly
                let nextIdx = (selectedFolderIndex + 1) % folders.count
                openFolder(folders[nextIdx])
                return .handled
            }

        // ↵ Return — Open folder (if at root) or insert snippet (if inside folder or search)
        case Self.keyReturn:
            if isSearching {
                guard !searchResults.isEmpty else { return .handled }
                let idx = min(selectedSearchResultIndex, searchResults.count - 1)
                switch searchResults[idx] {
                case .snippet(let snippet, _, _, _):
                    return .insertSnippet(snippet.content)
                case .folder(let folder, _):
                    openFolder(folder)
                    return .handled
                }
            } else if activeFolder == nil {
                openSelectedFolder()
                return .handled
            } else {
                let snippets = currentSnippets
                guard !snippets.isEmpty else { return .handled }
                let idx = min(selectedSnippetIndex, snippets.count - 1)
                return .insertSnippet(snippets[idx].content)
            }

        // ⎋ Escape — Clear search or close overlay
        case Self.keyEscape:
            if isSearching {
                searchText = ""
                return .handled
            }
            return .closeOverlay

        // ⌫ Delete — let text field handle during search, suppress beep when empty
        case Self.keyDelete:
            if isSearching && !searchText.isEmpty {
                return .ignored
            }
            return .handled

        default:
            return .ignored
        }
    }
}
