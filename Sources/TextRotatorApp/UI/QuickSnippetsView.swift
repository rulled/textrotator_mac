import SwiftUI
import AppKit
import TextRotatorCore

public struct QuickSnippetsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var navState: QuickSnippetsNavigationState
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool

    public init(
        coordinator: AppCoordinator,
        navState: QuickSnippetsNavigationState? = nil
    ) {
        self.coordinator = coordinator
        self.navState = navState ?? QuickSnippetsNavigationState(folders: coordinator.folders)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Permanent Search Header Bar
            headerView

            Divider()

            // Horizontal Folder Tabs Bar (Visible when not actively searching)
            if !navState.isSearching && !navState.folders.isEmpty {
                folderTabsBar
                Divider()
            }

            // Main Content Area: Instant Snippets List or Unified Search Results
            ZStack {
                if navState.isSearching {
                    unifiedSearchResultsView
                        .transition(.opacity)
                } else {
                    currentFolderSnippetsListView
                        .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Bottom Navigation Hints Bar
            footerHintsBar
        }
        .frame(width: 440, height: 350)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .overlay(AppTheme.panelBackgroundStroke(for: colorScheme))
        .animation(AppTheme.springFast, value: navState.selectedFolderIndex)
        .animation(AppTheme.springFast, value: navState.isSearching)
        .onAppear {
            navState.folders = coordinator.folders
            isSearchFocused = true
        }
        .onChange(of: coordinator.folders) { _, newFolders in
            navState.folders = newFolders
        }
    }

    // MARK: - Permanent Search Header View

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13, weight: .medium))

            TextField("Умный поиск по папкам и сниппетам...", text: $navState.searchText)
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

    // MARK: - Horizontal Folder Tabs Bar

    private var folderTabsBar: some View {
        ScrollViewReader { tabProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(navState.folders.enumerated()), id: \.element.id) { index, folder in
                        let isSelected = (navState.selectedFolderIndex == index)
                        Button {
                            navState.selectFolder(index: index)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isSelected ? "folder.fill" : "folder")
                                    .font(.system(size: 11))

                                Text(folder.name)
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                    .lineLimit(1)

                                Text("\(folder.snippets.count)")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(
                                        isSelected
                                            ? Color.white.opacity(0.25)
                                            : Color.secondary.opacity(0.12)
                                    )
                                    .cornerRadius(AppTheme.badgeRadius)
                            }
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(
                                isSelected
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.10)
                            )
                            .cornerRadius(AppTheme.pillRadius)
                        }
                        .buttonStyle(LiteRowButtonStyle())
                        .id(index)
                        .accessibilityLabel("Папка \(folder.name), \(folder.snippets.count) сниппетов")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onChange(of: navState.selectedFolderIndex) { _, newIndex in
                withAnimation(AppTheme.springFast) {
                    tabProxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
    }

    // MARK: - Current Folder Snippets List View (Instant Display)

    private var currentFolderSnippetsListView: some View {
        Group {
            let snippets = navState.currentFolderSnippets
            if snippets.isEmpty {
                emptyPlaceholder(
                    icon: "doc.text",
                    message: "В этой папке пока нет сниппетов"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                                let isSelected = (navState.selectedSnippetIndex == index)
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
                    .onChange(of: navState.selectedSnippetIndex) { _, newIndex in
                        withAnimation(AppTheme.springFast) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Unified Search Results View

    private var unifiedSearchResultsView: some View {
        Group {
            if navState.searchResults.isEmpty {
                emptyPlaceholder(icon: "magnifyingglass", message: "Ничего не найдено")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(navState.searchResults.enumerated()), id: \.element.id) { index, item in
                                let isSelected = (navState.selectedSearchResultIndex == index)
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

                                            if !folderName.isEmpty {
                                                Text("📁 \(folderName)")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.secondary.opacity(0.1))
                                                    .cornerRadius(AppTheme.badgeRadius)
                                            }
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
                    .onChange(of: navState.selectedSearchResultIndex) { _, newIndex in
                        withAnimation(AppTheme.springFast) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer Hints Bar

    private var footerHintsBar: some View {
        HStack(spacing: 12) {
            if navState.isSearching {
                hintItem(keys: "↑↓", label: "Навигация")
                hintItem(keys: "↵", label: "Вставить")
                hintItem(keys: "esc", label: "Очистить")
            } else {
                hintItem(keys: "↑↓", label: "Сниппет")
                hintItem(keys: "←→ / ⇥", label: "Папка")
                hintItem(keys: "↵", label: "Вставить")
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

    // MARK: - Empty State Placeholder

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

// MARK: - Minimalist Row Button Style with Instant Press Scale

private struct LiteRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(AppTheme.springFast, value: configuration.isPressed)
    }
}
