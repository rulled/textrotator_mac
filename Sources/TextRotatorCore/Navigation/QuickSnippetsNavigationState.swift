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
/// Layout: horizontal folder tabs + vertical snippet list + unified search.
/// - `↓` / `↑`: Move selection through snippets (or search results).
/// - `→` / `←` / `Tab`: Switch folder tabs.
/// - `Enter`: Insert selected snippet.
/// - `Escape`: Clear search, or dismiss overlay.
@MainActor
public final class QuickSnippetsNavigationState: ObservableObject {

    // MARK: - Published State

    @Published public var folders: [FolderWithSnippets] = [] {
        didSet { rebuildState() }
    }

    @Published public var searchText: String = "" {
        didSet { rebuildState() }
    }

    @Published public private(set) var selectedFolderIndex: Int = 0
    @Published public private(set) var selectedSnippetIndex: Int = 0
    @Published public private(set) var selectedSearchResultIndex: Int = 0
    @Published public private(set) var searchResults: [SmartSearchItem] = []

    // MARK: - Computed

    public var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var currentFolder: FolderWithSnippets? {
        guard !folders.isEmpty else { return nil }
        return folders[selectedFolderIndex]
    }

    public var currentFolderSnippets: [SnippetItem] {
        currentFolder?.snippets ?? []
    }

    // MARK: - Init

    public init(folders: [FolderWithSnippets] = []) {
        self.folders = folders
        // didSet doesn't fire during init, so call manually
        rebuildState()
    }

    // MARK: - State Rebuild (single point of truth)

    private func rebuildState() {
        // Clamp folder index
        if folders.isEmpty {
            if selectedFolderIndex != 0 { selectedFolderIndex = 0 }
            if selectedSnippetIndex != 0 { selectedSnippetIndex = 0 }
        } else {
            let maxFolder = folders.count - 1
            if selectedFolderIndex > maxFolder {
                selectedFolderIndex = maxFolder
            }
            // Clamp snippet index to current folder
            let snippetCount = currentFolderSnippets.count
            if snippetCount == 0 {
                if selectedSnippetIndex != 0 { selectedSnippetIndex = 0 }
            } else if selectedSnippetIndex >= snippetCount {
                selectedSnippetIndex = snippetCount - 1
            }
        }

        // Recompute search results (once, cached as stored property)
        let newResults = isSearching
            ? SmartSearchEngine.search(query: searchText, in: folders)
            : []
        searchResults = newResults

        // Clamp search result index
        if searchResults.isEmpty {
            if selectedSearchResultIndex != 0 { selectedSearchResultIndex = 0 }
        } else if selectedSearchResultIndex >= searchResults.count {
            selectedSearchResultIndex = searchResults.count - 1
        }
    }

    // MARK: - Navigation API

    public func selectFolder(index: Int) {
        guard !folders.isEmpty else { return }
        let clamped = max(0, min(index, folders.count - 1))
        selectedFolderIndex = clamped
        selectedSnippetIndex = 0
        if isSearching { searchText = "" }
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

        // ↓ Down Arrow — navigate snippets / search results downward
        case Self.keyDownArrow:
            if isSearching {
                if selectedSearchResultIndex < searchResults.count - 1 {
                    selectedSearchResultIndex += 1
                }
            } else if selectedSnippetIndex < currentFolderSnippets.count - 1 {
                selectedSnippetIndex += 1
            }
            return .handled

        // ↑ Up Arrow — navigate snippets / search results upward
        case Self.keyUpArrow:
            if isSearching {
                if selectedSearchResultIndex > 0 {
                    selectedSearchResultIndex -= 1
                }
            } else if selectedSnippetIndex > 0 {
                selectedSnippetIndex -= 1
            }
            return .handled

        // → Right Arrow — switch folder tab right (passthrough during search for text cursor)
        case Self.keyRightArrow:
            guard !isSearching else { return .ignored }
            if selectedFolderIndex < folders.count - 1 {
                selectedFolderIndex += 1
                selectedSnippetIndex = 0
            }
            return .handled

        // ← Left Arrow — switch folder tab left (passthrough during search for text cursor)
        case Self.keyLeftArrow:
            guard !isSearching else { return .ignored }
            if selectedFolderIndex > 0 {
                selectedFolderIndex -= 1
                selectedSnippetIndex = 0
            }
            return .handled

        // ⇥ Tab — cycle to next folder
        case Self.keyTab:
            guard !isSearching, !folders.isEmpty else { return .ignored }
            selectedFolderIndex = (selectedFolderIndex + 1) % folders.count
            selectedSnippetIndex = 0
            return .handled

        // ↵ Return — insert snippet or open folder from search
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
            } else {
                let snippets = currentFolderSnippets
                guard !snippets.isEmpty else { return .handled }
                let idx = min(selectedSnippetIndex, snippets.count - 1)
                return .insertSnippet(snippets[idx].content)
            }

        // ⎋ Escape — clear search or close overlay
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
