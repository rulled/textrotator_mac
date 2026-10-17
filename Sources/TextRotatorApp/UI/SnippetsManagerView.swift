import SwiftUI
import AppKit
import TextRotatorCore

public struct SnippetsManagerView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var selectedFolderId: Int64?

    // Folder Actions State
    @State private var isCreatingFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var editingFolderId: Int64?
    @State private var editingFolderName: String = ""
    @State private var folderPendingDeletion: FolderWithSnippets?
    @FocusState private var isFolderRenameFocused: Bool
    @FocusState private var isFolderCreateFocused: Bool

    // Snippet Inline Actions State
    @State private var isAddingSnippet: Bool = false
    @State private var newSnippetContent: String = ""
    @State private var editingSnippetId: Int64?
    @State private var editingSnippetText: String = ""
    @FocusState private var isSnippetEditFocused: Bool

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        if let first = coordinator.folders.first {
            _selectedFolderId = State(initialValue: first.id)
        }
    }

    private var selectedFolder: FolderWithSnippets? {
        if let id = selectedFolderId {
            return coordinator.folders.first(where: { $0.id == id }) ?? coordinator.folders.first
        }
        return coordinator.folders.first
    }


    public var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .frame(minWidth: 720, minHeight: 460)
        .confirmationDialog(
            "Удалить папку «\(folderPendingDeletion?.name ?? "")»?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить папку", role: .destructive) {
                if let folder = folderPendingDeletion {
                    deleteFolder(folder)
                }
                folderPendingDeletion = nil
            }
            Button("Отмена", role: .cancel) {
                folderPendingDeletion = nil
            }
        } message: {
            Text("Все сниппеты в этой папке будут безвозвратно удалены.")
        }
    }

    // MARK: - Sidebar Content

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selectedFolderId) {
            Section("Папки") {
                if isCreatingFolder {
                    inlineNewFolderRow
                }

                ForEach(coordinator.folders) { folder in
                    folderSidebarRow(folder: folder)
                }
                .onMove(perform: moveFolders)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Папки")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(AppTheme.springFast) {
                        newFolderName = ""
                        isCreatingFolder = true
                        editingFolderId = nil
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Создать папку (вверху списка)")
                .accessibilityLabel("Создать новую папку")
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let folder = selectedFolder {
            VStack(spacing: 0) {
                snippetsListContainer(folder: folder)
                Divider()
                statusFooter
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(AppTheme.springFast) {
                            isAddingSnippet = true
                            newSnippetContent = ""
                            editingSnippetId = nil
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .help("Добавить сниппет (Cmd+N)")
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel("Добавить новый сниппет")
                }
            }
        } else {
            ContentUnavailableView(
                "Папка не выбрана",
                systemImage: "folder",
                description: Text("Выберите папку из списка слева или создайте новую.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Snippets List Container

    @ViewBuilder
    private func snippetsListContainer(folder: FolderWithSnippets) -> some View {
        if folder.snippets.isEmpty && !isAddingSnippet {
            ContentUnavailableView {
                Label("В этой папке пока нет сниппетов", systemImage: "doc.text")
            } description: {
                Text("Создайте первый сниппет для быстрого доступа по хоткею.")
            } actions: {
                Button("Создать сниппет") {
                    withAnimation(AppTheme.springFast) {
                        isAddingSnippet = true
                        newSnippetContent = ""
                    }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if isAddingSnippet {
                    inlineNewSnippetCard(folderId: folder.id)
                }

                ForEach(folder.snippets) { snippet in
                    if editingSnippetId == snippet.id {
                        inlineSnippetEditor(snippet: snippet)
                    } else {
                        SnippetDetailRow(
                            snippet: snippet,
                            onEdit: {
                                startEditingSnippet(snippet)
                            },
                            onDelete: {
                                deleteSnippet(snippet)
                            }
                        )
                    }
                }
                .onMove(perform: moveSnippets)
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Status Footer

    private var statusFooter: some View {
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
                Text("F2: Перевод выделения")
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

    // MARK: - Inline New Folder Row (Top of sidebar)

    private var inlineNewFolderRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.badge.plus")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))

            TextField("Название папки...", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .focused($isFolderCreateFocused)
                .onSubmit {
                    submitCreateFolder()
                }

            Button {
                submitCreateFolder()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Сохранить (Enter)")

            Button {
                cancelCreateFolder()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Отмена (Escape)")
        }
        .padding(.vertical, 2)
        .onAppear {
            isFolderCreateFocused = true
        }
    }

    // MARK: - Folder Sidebar Row (with inline rename)

    @ViewBuilder
    private func folderSidebarRow(folder: FolderWithSnippets) -> some View {
        if editingFolderId == folder.id {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13))

                TextField("Название папки", text: $editingFolderName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($isFolderRenameFocused)
                    .onSubmit {
                        saveFolderName(folder: folder)
                    }

                Button {
                    saveFolderName(folder: folder)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Сохранить имя")

                Button {
                    editingFolderId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Отмена")
            }
            .padding(.vertical, 2)
            .onAppear {
                isFolderRenameFocused = true
            }
        } else {
            NavigationLink(value: folder.id) {
                Label(folder.name, systemImage: "folder")
                    .font(.system(size: 13))
            }
            .contextMenu {
                Button("Переименовать...") {
                    startRenamingFolder(folder)
                }
                Divider()
                Button("Удалить папку...", role: .destructive) {
                    folderPendingDeletion = folder
                }
            }
        }
    }

    // MARK: - Inline New Snippet Creator Card

    private func inlineNewSnippetCard(folderId: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Новый сниппет")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                Spacer()
            }

            TextEditor(text: $newSnippetContent)
                .font(.system(size: 13))
                .frame(minHeight: 70, maxHeight: 150)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.2)
                )

            HStack {
                Spacer()
                Button("Отмена") {
                    withAnimation(AppTheme.springFast) {
                        isAddingSnippet = false
                        newSnippetContent = ""
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                Button("Добавить") {
                    addSnippet()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Inline Snippet Editor Card (In-container editing)

    private func inlineSnippetEditor(snippet: SnippetItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Редактирование сниппета", systemImage: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                Spacer()
            }

            TextEditor(text: $editingSnippetText)
                .font(.system(size: 13))
                .frame(minHeight: 80, maxHeight: 180)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                )
                .focused($isSnippetEditFocused)

            HStack {
                Spacer()
                Button("Отмена") {
                    withAnimation(AppTheme.springFast) {
                        editingSnippetId = nil
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                Button("Сохранить") {
                    saveSnippetEdit(snippetId: snippet.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(editingSnippetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            isSnippetEditFocused = true
        }
    }

    // MARK: - Actions

    private func moveFolders(from source: IndexSet, to destination: Int) {
        var reordered = coordinator.folders
        reordered.move(fromOffsets: source, toOffset: destination)
        let order = reordered.map(\.id)
        do {
            try coordinator.database.reorderFolders(order: order)
            coordinator.reloadDatabaseData()
            AppTheme.hapticClick()
        } catch {
            print("Failed to reorder folders: \(error)")
        }
    }

    private func moveSnippets(from source: IndexSet, to destination: Int) {
        guard let folder = selectedFolder else { return }
        var reordered = folder.snippets
        reordered.move(fromOffsets: source, toOffset: destination)
        let order = reordered.map(\.id)
        do {
            try coordinator.database.reorderSnippets(folderId: folder.id, order: order)
            coordinator.reloadDatabaseData()
            AppTheme.hapticClick()
        } catch {
            print("Failed to reorder snippets: \(error)")
        }
    }

    private func startRenamingFolder(_ folder: FolderWithSnippets) {
        editingFolderName = folder.name
        withAnimation(AppTheme.springFast) {
            editingFolderId = folder.id
        }
    }

    private func saveFolderName(folder: FolderWithSnippets) {
        let trimmed = editingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editingFolderId = nil
            return
        }
        do {
            try coordinator.database.updateFolder(id: folder.id, name: trimmed)
            coordinator.reloadDatabaseData()
            AppTheme.hapticClick()
        } catch {
            print("Failed to update folder name: \(error)")
        }
        withAnimation(AppTheme.springFast) {
            editingFolderId = nil
        }
    }

    private func submitCreateFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            cancelCreateFolder()
            return
        }
        do {
            let created = try coordinator.database.createFolder(name: name)
            // Position the newly created folder at the very top of the list
            var order = [created.id]
            order.append(contentsOf: coordinator.folders.map(\.id).filter { $0 != created.id })
            try? coordinator.database.reorderFolders(order: order)

            coordinator.reloadDatabaseData()
            selectedFolderId = created.id
            AppTheme.hapticClick()
        } catch {
            print("Failed to create folder: \(error)")
        }
        withAnimation(AppTheme.springFast) {
            isCreatingFolder = false
            newFolderName = ""
        }
    }

    private func cancelCreateFolder() {
        withAnimation(AppTheme.springFast) {
            isCreatingFolder = false
            newFolderName = ""
        }
    }

    private func deleteFolder(_ folder: FolderWithSnippets) {
        do {
            try coordinator.database.deleteFolder(id: folder.id)
            coordinator.reloadDatabaseData()
            if selectedFolderId == folder.id {
                selectedFolderId = coordinator.folders.first?.id
            }
            AppTheme.hapticClick()
        } catch {
            print("Failed to delete folder: \(error)")
        }
    }

    private func startEditingSnippet(_ snippet: SnippetItem) {
        editingSnippetText = snippet.content
        withAnimation(AppTheme.springFast) {
            isAddingSnippet = false
            editingSnippetId = snippet.id
        }
    }

    private func saveSnippetEdit(snippetId: Int64) {
        let trimmed = editingSnippetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try coordinator.database.updateSnippet(id: snippetId, content: trimmed)
            coordinator.reloadDatabaseData()
            AppTheme.hapticSuccess()
        } catch {
            print("Failed to update snippet: \(error)")
        }
        withAnimation(AppTheme.springFast) {
            editingSnippetId = nil
        }
    }

    private func addSnippet() {
        guard let folder = selectedFolder else { return }
        let text = newSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            _ = try coordinator.database.createSnippet(folderId: folder.id, content: text)
            coordinator.reloadDatabaseData()
            AppTheme.hapticSuccess()
        } catch {
            print("Failed to create snippet: \(error)")
        }
        withAnimation(AppTheme.springFast) {
            isAddingSnippet = false
            newSnippetContent = ""
        }
    }

    private func deleteSnippet(_ snippet: SnippetItem) {
        do {
            try coordinator.database.deleteSnippet(id: snippet.id)
            coordinator.reloadDatabaseData()
            AppTheme.hapticClick()
        } catch {
            print("Failed to delete snippet: \(error)")
        }
    }
}

// MARK: - Snippet Detail Row (without copy button)

private struct SnippetDetailRow: View {
    let snippet: SnippetItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 2)

            Text(snippet.content)
                .font(.system(size: 13))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Actions: Edit and Delete only (Copy button removed)
            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Редактировать текст на месте")
                .accessibilityLabel("Редактировать сниппет")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Удалить сниппет")
                .accessibilityLabel("Удалить сниппет")
            }
            .opacity(isHovered ? 1.0 : 0.4)
            .animation(AppTheme.springFast, value: isHovered)
        }
        .padding(.vertical, 6)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(snippet.content)
    }
}
