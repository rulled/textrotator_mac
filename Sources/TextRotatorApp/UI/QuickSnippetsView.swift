import SwiftUI
import TextRotatorCore

public struct QuickSnippetsView: View {
    @ObservedObject var coordinator: AppCoordinator
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
            // Header / Search Bar
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
                            coordinator.insertSnippetText(displayedSnippets[idx].content)
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
                }

                Button {
                    coordinator.quickSnippetsPanel?.close()
                    coordinator.restoreForegroundApp()
                } label: {
                    Text("esc")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            Divider()

            // Folder Switcher Bar (Tabs)
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

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(coordinator.folders.enumerated()), id: \.element.id) { index, folder in
                                Button {
                                    selectedFolderIndex = index
                                    selectedSnippetIndex = 0
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(folder.name)
                                            .font(.system(size: 11, weight: selectedFolderIndex == index ? .semibold : .regular))
                                        Text("\(folder.snippets.count)")
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundColor(selectedFolderIndex == index ? .primary : .secondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(
                                                selectedFolderIndex == index
                                                ? Color.primary.opacity(0.15)
                                                : Color.secondary.opacity(0.1)
                                            )
                                            .cornerRadius(6)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        selectedFolderIndex == index
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear
                                    )
                                    .cornerRadius(6)
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
                }
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.4))

                Divider()
            }

            // Snippets List
            if displayedSnippets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "В папке нет сниппетов" : "Ничего не найдено")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(displayedSnippets.enumerated()), id: \.element.id) { index, snippet in
                                SnippetRow(
                                    snippet: snippet,
                                    index: index,
                                    isSelected: selectedSnippetIndex == index
                                ) {
                                    coordinator.insertSnippetText(snippet.content)
                                }
                                .id(index)
                            }
                        }
                        .padding(6)
                    }
                    .onKeyPress(.downArrow) {
                        if selectedSnippetIndex < displayedSnippets.count - 1 {
                            selectedSnippetIndex += 1
                            proxy.scrollTo(selectedSnippetIndex)
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if selectedSnippetIndex > 0 {
                            selectedSnippetIndex -= 1
                            proxy.scrollTo(selectedSnippetIndex)
                        }
                        return .handled
                    }
                }
            }

            Divider()

            // Footer / Shortcuts guide
            HStack {
                Text("↵ Вставить")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("← → Папка")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("1-9 Выбор")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 380, height: 320)
        .background(.regularMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .onKeyPress { keyPress in
            // Handle digits 1-9 for instant insertion
            if let character = keyPress.characters.first, let digit = Int(String(character)), (1...9).contains(digit) {
                let targetIndex = digit - 1
                if targetIndex < displayedSnippets.count {
                    coordinator.insertSnippetText(displayedSnippets[targetIndex].content)
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
        selectedFolderIndex = (selectedFolderIndex + direction + count) % count
        selectedSnippetIndex = 0
    }
}

private struct SnippetRow: View {
    let snippet: SnippetItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                // Digit badge (1..9)
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            isSelected
                            ? Color.accentColor
                            : Color.secondary.opacity(0.15)
                        )
                        .cornerRadius(4)
                } else {
                    Spacer().frame(width: 16)
                }

                // Text preview
                Text(snippet.content)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected
                ? Color.accentColor.opacity(0.18)
                : Color.clear
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
