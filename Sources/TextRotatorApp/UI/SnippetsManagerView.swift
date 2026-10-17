import SwiftUI
import AppKit
import TextRotatorCore

public struct SnippetsManagerView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var selectedFolderId: Int64?
    @State private var searchText: String = ""
    @State private var isAddingFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var editingSnippet: SnippetItem?
    @State private var newSnippetContent: String = ""
    @State private var isAddingSnippet: Bool = false
    @State private var renamingFolder: FolderWithSnippets?
    @State private var renameFolderName: String = ""

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _selectedFolderId = State(initialValue: coordinator.folders.first?.id)
    }

    private var selectedFolder: FolderWithSnippets? {
        if let id = selectedFolderId {
            return coordinator.folders.first { $0.id == id }
        }
        return coordinator.folders.first
    }

    private var filteredSnippets: [SnippetItem] {
        guard let folder = selectedFolder else { return [] }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return folder.snippets
        }
        let query = searchText.lowercased()
        return folder.snippets.filter { $0.content.lowercased().contains(query) }
    }

    public var body: some View {
        NavigationSplitView {
            // MARK: - Folders Sidebar
            List(selection: $selectedFolderId) {
                Section("Папки") {
                    ForEach(coordinator.folders) { folder in
                        NavigationLink(value: folder.id) {
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                    .font(.system(size: 13))
                                Spacer()
                                Text("\(folder.snippets.count)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(6)
                            }
                        }
                        .contextMenu {
                            Button("Переименовать") {
                                renamingFolder = folder
                                renameFolderName = folder.name
                            }
                            Divider()
                            Button("Удалить папку", role: .destructive) {
                                deleteFolder(folder)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Папки")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newFolderName = ""
                        isAddingFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .help("Создать папку")
                }
            }
        } detail: {
            // MARK: - Snippets Detail View
            if let folder = selectedFolder {
                VStack(spacing: 0) {
                    // Header Toolbar
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                                .font(.system(size: 18, weight: .bold))
                            Text("\(folder.snippets.count) сниппетов")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Search
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                            TextField("Поиск по тексту...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .frame(width: 200)

                        // Add Snippet Button
                        Button {
                            newSnippetContent = ""
                            isAddingSnippet = true
                        } label: {
                            Label("Добавить", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    // Snippets List
                    if filteredSnippets.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "doc.text")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(searchText.isEmpty ? "В этой папке пока нет шаблонов" : "По запросу ничего не найдено")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            if searchText.isEmpty {
                                Button("Создать первый сниппет") {
                                    newSnippetContent = ""
                                    isAddingSnippet = true
                                }
                                .buttonStyle(.bordered)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(Array(filteredSnippets.enumerated()), id: \.element.id) { index, snippet in
                                SnippetDetailRow(
                                    snippet: snippet,
                                    index: index,
                                    onEdit: {
                                        editingSnippet = snippet
                                    },
                                    onDelete: {
                                        deleteSnippet(snippet)
                                    },
                                    onCopy: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(snippet.content, forType: .string)
                                    }
                                )
                            }
                        }
                        .listStyle(.inset)
                    }

                    Divider()

                    // System Info / Status Footer
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(coordinator.textIO.isAccessibilityGranted() ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(coordinator.textIO.isAccessibilityGranted() ? "Accessibility активен" : "Accessibility не разрешен")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 12) {
                            Text("F1: Мгновенный перевод")
                            Text("F3: Панель сниппетов")
                            Text("F4: Переводчик")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                }
            } else {
                VStack(spacing: 8) {
                    Text("Выберите или создайте папку")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        // Dialog: Add Folder
        .sheet(isPresented: $isAddingFolder) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Новая папка")
                    .font(.headline)

                TextField("Название папки", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Отмена") {
                        isAddingFolder = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Создать") {
                        createFolder()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
        // Dialog: Rename Folder
        .sheet(item: $renamingFolder) { folder in
            VStack(alignment: .leading, spacing: 14) {
                Text("Переименовать папку")
                    .font(.headline)

                TextField("Новое название", text: $renameFolderName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Отмена") {
                        renamingFolder = nil
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Сохранить") {
                        if !renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            try? coordinator.database.updateFolder(id: folder.id, name: renameFolderName)
                            coordinator.reloadDatabaseData()
                        }
                        renamingFolder = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
        // Dialog: Add Snippet
        .sheet(isPresented: $isAddingSnippet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Новый сниппет")
                    .font(.headline)

                TextEditor(text: $newSnippetContent)
                    .font(.system(size: 13))
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                HStack {
                    Spacer()
                    Button("Отмена") {
                        isAddingSnippet = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Добавить") {
                        addSnippet()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 440, height: 260)
        }
        // Dialog: Edit Snippet
        .sheet(item: $editingSnippet) { snippet in
            EditSnippetSheet(snippet: snippet) { updatedText in
                try? coordinator.database.updateSnippet(id: snippet.id, content: updatedText)
                coordinator.reloadDatabaseData()
                editingSnippet = nil
            } onCancel: {
                editingSnippet = nil
            }
        }
    }

    // MARK: - Actions

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let created = try coordinator.database.createFolder(name: name)
            coordinator.reloadDatabaseData()
            selectedFolderId = created.id
        } catch {
            print("Failed to create folder: \(error)")
        }
        isAddingFolder = false
    }

    private func deleteFolder(_ folder: FolderWithSnippets) {
        do {
            try coordinator.database.deleteFolder(id: folder.id)
            coordinator.reloadDatabaseData()
            if selectedFolderId == folder.id {
                selectedFolderId = coordinator.folders.first?.id
            }
        } catch {
            print("Failed to delete folder: \(error)")
        }
    }

    private func addSnippet() {
        guard let folder = selectedFolder else { return }
        let text = newSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            _ = try coordinator.database.createSnippet(folderId: folder.id, content: text)
            coordinator.reloadDatabaseData()
        } catch {
            print("Failed to create snippet: \(error)")
        }
        isAddingSnippet = false
    }

    private func deleteSnippet(_ snippet: SnippetItem) {
        do {
            try coordinator.database.deleteSnippet(id: snippet.id)
            coordinator.reloadDatabaseData()
        } catch {
            print("Failed to delete snippet: \(error)")
        }
    }
}

// MARK: - Snippet Detail Row

private struct SnippetDetailRow: View {
    let snippet: SnippetItem
    let index: Int
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Index badge
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(5)

            // Content
            Text(snippet.content)
                .font(.system(size: 13))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Actions
            HStack(spacing: 6) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Скопировать в буфер")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Редактировать")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Удалить")
            }
            .opacity(isHovered ? 1.0 : 0.4)
        }
        .padding(.vertical, 6)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Edit Snippet Sheet

private struct EditSnippetSheet: View {
    let snippet: SnippetItem
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var content: String

    init(snippet: SnippetItem, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.snippet = snippet
        self.onSave = onSave
        self.onCancel = onCancel
        _content = State(initialValue: snippet.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Редактирование сниппета")
                .font(.headline)

            TextEditor(text: $content)
                .font(.system(size: 13))
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Отмена", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Сохранить") {
                    onSave(content)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440, height: 260)
    }
}
