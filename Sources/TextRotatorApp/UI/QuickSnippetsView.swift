import SwiftUI
import AppKit
import TextRotatorCore

public struct QuickSnippetsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme

    // Navigation State: nil = Root (Folders or Unified Search), non-nil = Inside specific Folder
    @State private var activeFolder: FolderWithSnippets? = nil

    // Selection Indices
    @State private var selectedFolderIndex: Int = 0
    @State private var selectedSnippetIndex: Int = 0
    @State private var selectedSearchResultIndex: Int = 0

    // Search Query
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Computed Properties

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Unified smart search results when at root level
    private var searchResults: [SmartSearchItem] {
        SmartSearchEngine.search(query: searchText, in: coordinator.folders)
    }

    /// Snippets displayed when inside a folder (filtered if search text present)
    private var displayedFolderSnippets: [SnippetItem] {
        guard let folder = activeFolder else { return [] }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return folder.snippets
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return folder.snippets.filter { snippet in
            SmartSearchEngine.calculateScore(query: query, candidate: snippet.content) > 0
        }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main Content Area
            ZStack {
                if activeFolder != nil {
                    // LEVEL 2: Inside Folder (Folder Detail View)
                    folderDetailListView
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                        )
                } else if isSearching {
                    // UNIFIED SEARCH: Matching Folders + Matching Snippets with Badges
                    unifiedSearchResultsView
                        .transition(.opacity)
                } else {
                    // ROOT LEVEL: Clean Folders List
                    rootFoldersListView
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                        )
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 420, height: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .overlay(AppTheme.panelBackgroundStroke(for: colorScheme))
        .animation(AppTheme.springFast, value: activeFolder?.id)
        .animation(AppTheme.springFast, value: isSearching)
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
    }

    // MARK: - Header View

    @ViewBuilder
    private var headerView: some View {
        if let folder = activeFolder {
            // Level 2 Header: Back button + Folder title
            HStack(spacing: 8) {
                Button {
                    backToRoot()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Папки")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(AppTheme.pillRadius)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Назад к списку папок")

                Text(folder.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                searchField

                closeButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        } else {
            // Level 1 / Search Header: Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13, weight: .medium))

                TextField("Умный поиск по папкам и текстам...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _, _ in
                        selectedSearchResultIndex = 0
                        selectedFolderIndex = 0
                        selectedSnippetIndex = 0
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        selectedSearchResultIndex = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить поиск")
                }

                closeButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 10))

            TextField("Поиск...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .focused($isSearchFocused)
                .frame(width: 90)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(AppTheme.badgeRadius)
    }

    private var closeButton: some View {
        Button {
            coordinator.quickSnippetsPanel?.close()
            coordinator.restoreForegroundApp()
        } label: {
            Text("esc")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(AppTheme.badgeRadius)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Закрыть (Escape)")
        .accessibilityLabel("Закрыть")
    }

    // MARK: - Root: Folders List View (Empty Search)

    private var rootFoldersListView: some View {
        Group {
            if coordinator.folders.isEmpty {
                emptyPlaceholder(icon: "folder", message: "Папок пока нет")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(coordinator.folders.enumerated()), id: \.element.id) { index, folder in
                                let isSelected = (selectedFolderIndex == index)
                                Button {
                                    openFolder(folder)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isSelected ? "folder.fill" : "folder")
                                            .foregroundColor(isSelected ? .accentColor : .secondary)
                                            .font(.system(size: 13))

                                        Text(folder.name)
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text("\(folder.snippets.count)")
                                            .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(AppTheme.badgeRadius)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.secondary.opacity(0.7))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected
                                            ? Color.accentColor.opacity(0.16)
                                            : Color.clear
                                    )
                                    .cornerRadius(AppTheme.pillRadius)
                                }
                                .buttonStyle(LiteRowButtonStyle())
                                .id(index)
                                .accessibilityLabel("Папка \(folder.name), \(folder.snippets.count) сниппетов")
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selectedFolderIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Unified Search Results View (Matching Folders + Snippets with Badges)

    private var unifiedSearchResultsView: some View {
        Group {
            if searchResults.isEmpty {
                emptyPlaceholder(icon: "magnifyingglass", message: "Ничего не найдено")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, item in
                                let isSelected = (selectedSearchResultIndex == index)
                                Button {
                                    executeSearchItem(item)
                                } label: {
                                    HStack(spacing: 8) {
                                        switch item {
                                        case .folder(let folder, _):
                                            Image(systemName: isSelected ? "folder.fill" : "folder")
                                                .foregroundColor(isSelected ? .accentColor : .secondary)
                                                .font(.system(size: 13))

                                            Text(folder.name)
                                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)

                                            Spacer()

                                            HStack(spacing: 3) {
                                                Text("Папка")
                                                    .font(.system(size: 10, weight: .medium))
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 9, weight: .semibold))
                                            }
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(AppTheme.badgeRadius)

                                        case .snippet(let snippet, let folderName, _, _):
                                            Image(systemName: "text.quote")
                                                .foregroundColor(isSelected ? .accentColor : .secondary)
                                                .font(.system(size: 12))

                                            Text(snippet.content)
                                                .font(.system(size: 12.5))
                                                .foregroundColor(isSelected ? .primary : .primary.opacity(0.9))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            HStack(spacing: 3) {
                                                Image(systemName: "folder")
                                                    .font(.system(size: 9))
                                                Text(folderName)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .lineLimit(1)
                                            }
                                            .foregroundColor(isSelected ? .accentColor : .secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(
                                                isSelected
                                                    ? Color.accentColor.opacity(0.14)
                                                    : Color.secondary.opacity(0.1)
                                            )
                                            .cornerRadius(AppTheme.badgeRadius)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.clear
                                    )
                                    .cornerRadius(AppTheme.pillRadius)
                                }
                                .buttonStyle(LiteRowButtonStyle())
                                .id(index)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selectedSearchResultIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Level 2: Inside Folder (Detail View)

    private var folderDetailListView: some View {
        Group {
            if displayedFolderSnippets.isEmpty {
                emptyPlaceholder(icon: "doc.text", message: searchText.isEmpty ? "В папке нет сниппетов" : "Сниппет не найден")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(displayedFolderSnippets.enumerated()), id: \.element.id) { index, snippet in
                                let isSelected = (selectedSnippetIndex == index)
                                Button {
                                    insertSnippet(snippet.content)
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "text.quote")
                                            .foregroundColor(isSelected ? .accentColor : .secondary)
                                            .font(.system(size: 12))
                                            .padding(.top, 2)

                                        Text(snippet.content)
                                            .font(.system(size: 12.5))
                                            .foregroundColor(isSelected ? .primary : .primary.opacity(0.9))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.clear
                                    )
                                    .cornerRadius(AppTheme.pillRadius)
                                }
                                .buttonStyle(LiteRowButtonStyle())
                                .id(index)
                                .help(snippet.content)
                                .accessibilityLabel("Сниппет: \(snippet.content)")
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selectedSnippetIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Empty State Placeholder

    private func emptyPlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(.secondary.opacity(0.5))
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard Handling

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        if activeFolder == nil {
            if isSearching {
                // NAVIGATION IN UNIFIED SEARCH RESULTS
                switch keyPress.key {
                case .downArrow:
                    if !searchResults.isEmpty && selectedSearchResultIndex < searchResults.count - 1 {
                        selectedSearchResultIndex += 1
                        AppTheme.hapticClick()
                    }
                    return .handled

                case .upArrow:
                    if selectedSearchResultIndex > 0 {
                        selectedSearchResultIndex -= 1
                        AppTheme.hapticClick()
                    }
                    return .handled

                case .return:
                    if !searchResults.isEmpty {
                        let idx = max(0, min(selectedSearchResultIndex, searchResults.count - 1))
                        executeSearchItem(searchResults[idx])
                    }
                    return .handled

                case .rightArrow:
                    if !searchResults.isEmpty {
                        let idx = max(0, min(selectedSearchResultIndex, searchResults.count - 1))
                        if case .folder(let folder, _) = searchResults[idx] {
                            openFolder(folder)
                            return .handled
                        }
                    }
                    return .ignored

                case .escape:
                    if !searchText.isEmpty {
                        searchText = ""
                        selectedSearchResultIndex = 0
                    } else {
                        coordinator.quickSnippetsPanel?.close()
                        coordinator.restoreForegroundApp()
                    }
                    return .handled

                default:
                    return .ignored
                }
            } else {
                // NAVIGATION IN ROOT FOLDERS
                switch keyPress.key {
                case .downArrow:
                    if !coordinator.folders.isEmpty && selectedFolderIndex < coordinator.folders.count - 1 {
                        selectedFolderIndex += 1
                        AppTheme.hapticClick()
                    }
                    return .handled

                case .upArrow:
                    if selectedFolderIndex > 0 {
                        selectedFolderIndex -= 1
                        AppTheme.hapticClick()
                    }
                    return .handled

                case .rightArrow, .return:
                    if !coordinator.folders.isEmpty {
                        let idx = max(0, min(selectedFolderIndex, coordinator.folders.count - 1))
                        openFolder(coordinator.folders[idx])
                    }
                    return .handled

                case .escape:
                    coordinator.quickSnippetsPanel?.close()
                    coordinator.restoreForegroundApp()
                    return .handled

                default:
                    return .ignored
                }
            }
        } else {
            // NAVIGATION INSIDE SPECIFIC FOLDER
            switch keyPress.key {
            case .downArrow:
                if !displayedFolderSnippets.isEmpty && selectedSnippetIndex < displayedFolderSnippets.count - 1 {
                    selectedSnippetIndex += 1
                    AppTheme.hapticClick()
                }
                return .handled

            case .upArrow:
                if selectedSnippetIndex > 0 {
                    selectedSnippetIndex -= 1
                    AppTheme.hapticClick()
                }
                return .handled

            case .return:
                if !displayedFolderSnippets.isEmpty {
                    let idx = max(0, min(selectedSnippetIndex, displayedFolderSnippets.count - 1))
                    insertSnippet(displayedFolderSnippets[idx].content)
                }
                return .handled

            case .leftArrow, .escape:
                backToRoot()
                return .handled

            case .delete:
                if searchText.isEmpty {
                    backToRoot()
                    return .handled
                }
                return .ignored

            default:
                return .ignored
            }
        }
    }

    // MARK: - Actions

    private func executeSearchItem(_ item: SmartSearchItem) {
        switch item {
        case .folder(let folder, _):
            openFolder(folder)
        case .snippet(let snippet, _, _, _):
            insertSnippet(snippet.content)
        }
    }

    private func openFolder(_ folder: FolderWithSnippets) {
        AppTheme.hapticClick()
        withAnimation(AppTheme.springFast) {
            activeFolder = folder
            selectedSnippetIndex = 0
            searchText = ""
        }
    }

    private func backToRoot() {
        AppTheme.hapticClick()
        withAnimation(AppTheme.springFast) {
            activeFolder = nil
            selectedFolderIndex = 0
            selectedSearchResultIndex = 0
            searchText = ""
        }
    }

    private func insertSnippet(_ text: String) {
        AppTheme.hapticSuccess()
        coordinator.insertSnippetText(text)
    }
}

// MARK: - Minimalist Row Button Style with Instant Press Scale

private struct LiteRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(AppTheme.springFast, value: configuration.isPressed)
    }
}
