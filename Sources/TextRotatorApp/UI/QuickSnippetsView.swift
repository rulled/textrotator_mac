import SwiftUI
import AppKit
import TextRotatorCore

public struct QuickSnippetsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme

    // Lite Mode State: nil = Root Folders Level, non-nil = Inside Folder Level
    @State private var activeFolder: FolderWithSnippets? = nil
    @State private var selectedFolderIndex: Int = 0
    @State private var selectedSnippetIndex: Int = 0
    @State private var searchText: String = ""

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Computed Filtered Collections

    private var filteredFolders: [FolderWithSnippets] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return coordinator.folders
        }
        return coordinator.folders.filter { folder in
            folder.name.lowercased().contains(query) ||
            folder.snippets.contains { $0.content.lowercased().contains(query) }
        }
    }

    private var displayedSnippets: [SnippetItem] {
        guard let folder = activeFolder else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return folder.snippets
        }
        return folder.snippets.filter { $0.content.lowercased().contains(query) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            if let folder = activeFolder {
                // Level 2 Header: Back button + Folder title
                HStack(spacing: 8) {
                    Button {
                        backToFolders()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Папки")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
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

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    closeButton
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            } else {
                // Level 1 Header: Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13, weight: .medium))

                    TextField("Поиск...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit {
                            if !filteredFolders.isEmpty {
                                let idx = max(0, min(selectedFolderIndex, filteredFolders.count - 1))
                                openFolder(filteredFolders[idx])
                            }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
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

            Divider()

            // MARK: - Body Content
            ZStack {
                if let _ = activeFolder {
                    // LEVEL 2: Snippets List (Inside Folder)
                    snippetsListView
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                        )
                } else {
                    // LEVEL 1: Folders List (Root)
                    foldersListView
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
        .frame(width: 380, height: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .overlay(AppTheme.panelBackgroundStroke(for: colorScheme))
        .animation(AppTheme.springFast, value: activeFolder?.id)
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
    }

    // MARK: - Close Button

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

    // MARK: - Level 1: Folders List View

    private var foldersListView: some View {
        Group {
            if filteredFolders.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(searchText.isEmpty ? "Папок пока нет" : "Папка не найдена")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredFolders.enumerated()), id: \.element.id) { index, folder in
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

    // MARK: - Level 2: Snippets List View

    private var snippetsListView: some View {
        Group {
            if displayedSnippets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(searchText.isEmpty ? "В папке нет сниппетов" : "Сниппет не найден")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(displayedSnippets.enumerated()), id: \.element.id) { index, snippet in
                                let isSelected = (selectedSnippetIndex == index)
                                Button {
                                    insertSnippet(snippet.content)
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(snippet.content)
                                            .font(.system(size: 12.5))
                                            .foregroundColor(isSelected ? .primary : .primary.opacity(0.88))
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

    // MARK: - Keyboard Navigation (Arrow Keys + Enter + Esc)

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        if activeFolder == nil {
            // LEVEL 1: FOLDERS NAVIGATION
            switch keyPress.key {
            case .downArrow:
                if !filteredFolders.isEmpty && selectedFolderIndex < filteredFolders.count - 1 {
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
                if !filteredFolders.isEmpty {
                    let idx = max(0, min(selectedFolderIndex, filteredFolders.count - 1))
                    openFolder(filteredFolders[idx])
                }
                return .handled

            case .escape:
                coordinator.quickSnippetsPanel?.close()
                coordinator.restoreForegroundApp()
                return .handled

            default:
                return .ignored
            }
        } else {
            // LEVEL 2: SNIPPETS NAVIGATION
            switch keyPress.key {
            case .downArrow:
                if !displayedSnippets.isEmpty && selectedSnippetIndex < displayedSnippets.count - 1 {
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
                if !displayedSnippets.isEmpty {
                    let idx = max(0, min(selectedSnippetIndex, displayedSnippets.count - 1))
                    insertSnippet(displayedSnippets[idx].content)
                }
                return .handled

            case .leftArrow, .escape:
                backToFolders()
                return .handled

            case .delete:
                // If search field is empty, Backspace goes back to folders
                if searchText.isEmpty {
                    backToFolders()
                    return .handled
                }
                return .ignored

            default:
                return .ignored
            }
        }
    }

    // MARK: - Actions

    private func openFolder(_ folder: FolderWithSnippets) {
        AppTheme.hapticClick()
        withAnimation(AppTheme.springFast) {
            activeFolder = folder
            selectedSnippetIndex = 0
            searchText = ""
        }
    }

    private func backToFolders() {
        AppTheme.hapticClick()
        withAnimation(AppTheme.springFast) {
            activeFolder = nil
            selectedSnippetIndex = 0
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
