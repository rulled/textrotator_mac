import SwiftUI
import AppKit
import TextRotatorCore

public struct QuickSnippetsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText: String = ""
    @State private var selectedFolderIndex: Int = 0
    @State private var selectedSnippetIndex: Int = 0

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    private var currentFolder: FolderWithSnippets? {
        guard !coordinator.folders.isEmpty else { return nil }
        let index = max(0, min(selectedFolderIndex, coordinator.folders.count - 1))
        return coordinator.folders[index]
    }

    private var displayedSnippets: [SnippetItem] {
        guard let folder = currentFolder else { return [] }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return folder.snippets
        } else {
            let query = searchText.lowercased()
            return folder.snippets.filter { $0.content.lowercased().contains(query) }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header & Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13, weight: .medium))

                TextField("Поиск сниппетов (или 1-9)...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        if !displayedSnippets.isEmpty {
                            let idx = max(0, min(selectedSnippetIndex, displayedSnippets.count - 1))
                            insertSnippet(displayedSnippets[idx].content)
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
                .help("Закрыть панель (Escape)")
                .accessibilityLabel("Закрыть")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            Divider()

            // MARK: - Folder Switcher Bar (Tabs)
            if coordinator.folders.count > 1 {
                HStack(spacing: 4) {
                    Button {
                        cycleFolder(direction: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("Предыдущая папка")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(coordinator.folders.enumerated()), id: \.element.id) { index, folder in
                                let isSelected = (selectedFolderIndex == index)
                                Button {
                                    withAnimation(AppTheme.springSmooth) {
                                        selectedFolderIndex = index
                                        selectedSnippetIndex = 0
                                    }
                                    AppTheme.hapticClick()
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(folder.name)
                                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                            .foregroundColor(isSelected ? .primary : .secondary)

                                        Text("\(folder.snippets.count)")
                                            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(
                                                isSelected
                                                    ? Color.primary.opacity(0.12)
                                                    : Color.secondary.opacity(0.08)
                                            )
                                            .cornerRadius(AppTheme.badgeRadius)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        isSelected
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.clear
                                    )
                                    .cornerRadius(AppTheme.pillRadius)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    Button {
                        cycleFolder(direction: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("Следующая папка")
                }
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
                .animation(AppTheme.springSmooth, value: selectedFolderIndex)

                Divider()
            }

            // MARK: - Snippets List
            if displayedSnippets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(searchText.isEmpty ? "В этой папке пока нет шаблонов" : "По запросу ничего не найдено")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(displayedSnippets.enumerated()), id: \.element.id) { index, snippet in
                                SnippetRow(
                                    snippet: snippet,
                                    index: index,
                                    isSelected: selectedSnippetIndex == index
                                ) {
                                    insertSnippet(snippet.content)
                                }
                                .id(index)
                            }
                        }
                        .padding(6)
                    }
                    .onKeyPress(.downArrow) {
                        if selectedSnippetIndex < displayedSnippets.count - 1 {
                            withAnimation(AppTheme.springFast) {
                                selectedSnippetIndex += 1
                            }
                            proxy.scrollTo(selectedSnippetIndex)
                            AppTheme.hapticClick()
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if selectedSnippetIndex > 0 {
                            withAnimation(AppTheme.springFast) {
                                selectedSnippetIndex -= 1
                            }
                            proxy.scrollTo(selectedSnippetIndex)
                            AppTheme.hapticClick()
                        }
                        return .handled
                    }
                }
            }

            Divider()

            // MARK: - Footer Navigation Guide
            HStack {
                HStack(spacing: 4) {
                    Text("↵")
                        .font(.system(size: 10, weight: .bold))
                    Text("Вставить")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Text("← →")
                        .font(.system(size: 10, weight: .bold))
                    Text("Папка")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Text("1-9")
                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    Text("Выбор")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 380, height: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .overlay(AppTheme.panelBackgroundStroke(for: colorScheme))
        .onKeyPress { keyPress in
            // Digits 1-9 direct instant insertion
            if let character = keyPress.characters.first, let digit = Int(String(character)), (1...9).contains(digit) {
                let targetIndex = digit - 1
                if targetIndex < displayedSnippets.count {
                    insertSnippet(displayedSnippets[targetIndex].content)
                    return .handled
                }
            }
            if keyPress.key == .leftArrow {
                cycleFolder(direction: -1)
                return .handled
            }
            if keyPress.key == .rightArrow {
                cycleFolder(direction: 1)
                return .handled
            }
            if keyPress.key == .escape {
                coordinator.quickSnippetsPanel?.close()
                coordinator.restoreForegroundApp()
                return .handled
            }
            return .ignored
        }
    }

    private func cycleFolder(direction: Int) {
        guard !coordinator.folders.isEmpty else { return }
        let count = coordinator.folders.count
        withAnimation(AppTheme.springSmooth) {
            selectedFolderIndex = (selectedFolderIndex + direction + count) % count
            selectedSnippetIndex = 0
        }
        AppTheme.hapticClick()
    }

    private func insertSnippet(_ text: String) {
        AppTheme.hapticSuccess()
        coordinator.insertSnippetText(text)
    }
}

// MARK: - Snippet Row with Spring Feedback & Truncation Tooltip

private struct SnippetRow: View {
    let snippet: SnippetItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                // Digit badge (1..9)
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(isSelected ? .white : .secondary)
                        .frame(width: 17, height: 17)
                        .background(
                            isSelected
                                ? Color.accentColor
                                : Color.secondary.opacity(0.14)
                        )
                        .cornerRadius(AppTheme.badgeRadius)
                } else {
                    Spacer().frame(width: 17)
                }

                // Text preview with full-text accessibility & tooltip
                Text(snippet.content)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.18)
                    : (isHovered ? Color.secondary.opacity(0.08) : Color.clear)
            )
            .cornerRadius(AppTheme.pillRadius)
        }
        .buttonStyle(SnippetRowButtonStyle())
        .help(snippet.content) // Resolves truncation accessibility trigger
        .onHover { hovering in
            withAnimation(AppTheme.springFast) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("Сниппет \(index + 1): \(snippet.content)")
        .accessibilityHint("Нажмите Enter или клавишу \(index + 1) для вставки")
    }
}

private struct SnippetRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(AppTheme.springFast, value: configuration.isPressed)
    }
}
