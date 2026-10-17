import SwiftUI
import AppKit
import TextRotatorCore

public struct QuickSnippetsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var navState: QuickSnippetsNavigationState
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool

    public init(coordinator: AppCoordinator, navState: QuickSnippetsNavigationState) {
        self.coordinator = coordinator
        self.navState = navState
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            ZStack {
                if navState.isSearching {
                    unifiedSearchResultsView
                        .transition(.opacity)
                } else if let folder = navState.activeFolder {
                    snippetsListView(folder: folder)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    foldersListView
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxHeight: .infinity)
            .animation(AppTheme.springFast, value: navState.activeFolder?.id)
            .animation(AppTheme.springFast, value: navState.isSearching)

            Divider()
            footerHintsBar
        }
        .frame(width: 400, height: 320)
        .background(.ultraThinMaterial)
        .activeGlassAppearance()
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .overlay(AppTheme.glassSpecularBorder(for: colorScheme))
        .onAppear {
            navState.folders = coordinator.folders
            isSearchFocused = true
        }
        .onChange(of: coordinator.folders) { _, newFolders in
            navState.folders = newFolders
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        if let folder = navState.activeFolder, !navState.isSearching {
            // Level 2 Header: Back breadcrumb + Folder Title + Count
            HStack(spacing: 8) {
                Button {
                    navState.backToFolders()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Папки")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .glassButton()
                .accessibilityLabel("Назад к списку папок")

                Text(folder.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                closeButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        } else {
            // Level 1 Header: Search Bar across all folders and snippets
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13, weight: .medium))

                TextField("Поиск папок и сниппетов...", text: $navState.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)

                if !navState.searchText.isEmpty {
                    Button {
                        navState.searchText = ""
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
            .padding(.vertical, 9)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        }
    }

    private var closeButton: some View {
        Button {
            coordinator.quickSnippetsPanel?.close()
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

    // MARK: - Level 1: Folders List

    private var foldersListView: some View {
        Group {
            if navState.folders.isEmpty {
                emptyPlaceholder(icon: "folder", message: "Нет доступных папок")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(navState.folders.enumerated()), id: \.element.id) { index, folder in
                                let isSelected = (navState.selectedFolderIndex == index)
                                Button {
                                    navState.openFolder(folder)
                                } label: {
                                    folderRow(folder: folder, isSelected: isSelected)
                                }
                                .buttonStyle(LiteRowButtonStyle())
                                .id(index)
                                .accessibilityLabel("Папка \(folder.name), \(folder.snippets.count) сниппетов")
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: navState.selectedFolderIndex) { _, newIndex in
                        withAnimation(AppTheme.springFast) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func folderRow(folder: FolderWithSnippets, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .accentColor : .secondary)

            Text(folder.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(isSelected ? 0.8 : 0.35))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(AppTheme.pillRadius)
    }

    // MARK: - Level 2: Snippets List (Inside Folder)

    private func snippetsListView(folder: FolderWithSnippets) -> some View {
        Group {
            let snippets = folder.snippets
            if snippets.isEmpty {
                emptyPlaceholder(icon: "doc.text", message: "В этой папке пока нет сниппетов")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                                let isSelected = (navState.selectedSnippetIndex == index)
                                Button {
                                    insertSnippet(snippet.content)
                                } label: {
                                    snippetRow(content: snippet.content, isSelected: isSelected)
                                }
                                .buttonStyle(LiteRowButtonStyle())
                                .id(index)
                                .help(snippet.content)
                                .accessibilityLabel("Сниппет: \(snippet.content)")
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: navState.selectedSnippetIndex) { _, newIndex in
                        withAnimation(AppTheme.springFast) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func snippetRow(content: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.7))
                .padding(.top, 2)

            Text(content)
                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .cornerRadius(AppTheme.pillRadius)
    }

    // MARK: - Unified Search Results

    private var unifiedSearchResultsView: some View {
        Group {
            let results = navState.searchResults
            if results.isEmpty {
                emptyPlaceholder(icon: "magnifyingglass", message: "Ничего не найдено")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                let isSelected = (navState.selectedSearchResultIndex == index)
                                Button {
                                    executeSearchItem(item)
                                } label: {
                                    searchResultRow(item: item, isSelected: isSelected)
                                }
                                .buttonStyle(LiteRowButtonStyle())
                                .id(index)
                                .accessibilityLabel(searchResultAccessibilityLabel(item))
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: navState.selectedSearchResultIndex) { _, newIndex in
                        withAnimation(AppTheme.springFast) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(item: SmartSearchItem, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            switch item {
            case .folder(let folder, _):
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(folder.name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(isSelected ? 0.8 : 0.35))

            case .snippet(let snippet, let folderName, _, _):
                Image(systemName: "quote.bubble")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.7))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    if !folderName.isEmpty {
                        Text(folderName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text(snippet.content)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .cornerRadius(AppTheme.pillRadius)
    }

    private func searchResultAccessibilityLabel(_ item: SmartSearchItem) -> String {
        switch item {
        case .folder(let folder, _):
            return "Папка \(folder.name)"
        case .snippet(let snippet, let folderName, _, _):
            let prefix = folderName.isEmpty ? "" : "из \(folderName): "
            return "Сниппет: \(prefix)\(snippet.content)"
        }
    }

    // MARK: - Footer

    private var footerHintsBar: some View {
        HStack(spacing: 12) {
            if navState.isSearching {
                hintItem(keys: "↑↓", label: "Навигация")
                hintItem(keys: "↵", label: "Выбрать")
                hintItem(keys: "esc", label: "Очистить")
            } else if navState.activeFolder != nil {
                hintItem(keys: "↑↓", label: "Текст")
                hintItem(keys: "↵", label: "Вставить")
                hintItem(keys: "←", label: "Папки")
                hintItem(keys: "esc", label: "Закрыть")
            } else {
                hintItem(keys: "↑↓", label: "Папка")
                hintItem(keys: "↵ / →", label: "Открыть")
                hintItem(keys: "esc", label: "Закрыть")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
    }

    private func hintItem(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(AppTheme.badgeRadius)
                .foregroundColor(.secondary)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty State

    private func emptyPlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(.secondary.opacity(0.5))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func executeSearchItem(_ item: SmartSearchItem) {
        switch item {
        case .folder(let folder, _):
            navState.openFolder(folder)
        case .snippet(let snippet, _, _, _):
            insertSnippet(snippet.content)
        }
    }

    private func insertSnippet(_ text: String) {
        AppTheme.hapticSuccess()
        coordinator.insertSnippetText(text)
    }
}

// MARK: - Row Button Style

private struct LiteRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(AppTheme.springFast, value: configuration.isPressed)
    }
}
