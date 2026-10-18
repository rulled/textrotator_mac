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
    @State private var isShowingSettings: Bool = false
    @State private var snippetPendingDeletion: SnippetItem?
    @Environment(\.colorScheme) private var colorScheme

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
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detailContent
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 780, minHeight: 480)
        .overlay {
            if isShowingSettings {
                ZStack {
                    // Plain content-area scrim (NO .ignoresSafeArea):
                    // In macOS NavigationSplitView, the sidebar's titlebar is transparent
                    // (its NSTitlebarBackgroundView is hidden) so the sidebar background extends to
                    // the top edge. If we used .ignoresSafeArea(), SwiftUI would darken the top-left
                    // under the traffic lights, and WindowManager's titlebarScrim would darken it AGAIN
                    // (double scrim -> top-left darker than top-right).
                    // Without .ignoresSafeArea(), SwiftUI darkens the content below the safe area (508pt),
                    // and WindowManager.titlebarScrim darkens the titlebar (52pt). They meet seamlessly.
                    Color.black.opacity(0.35)
                        .onTapGesture {
                            isShowingSettings = false
                        }

                    SettingsSheetView(coordinator: coordinator, isPresented: $isShowingSettings)
                        // thinMaterial: adds luminous tint so the modal reads as bright
                        // over the dark scrim behind it.
                        .background(.thinMaterial)
                        .activeGlassAppearance()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
                        .overlay(AppTheme.glassSpecularBorder(for: colorScheme))
                        .shadow(color: Color.black.opacity(0.35), radius: 32, y: 12)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(AppTheme.springFast, value: isShowingSettings)
        .onChange(of: isShowingSettings) { _, shown in
            WindowManager.shared.setTitlebarDimmed(shown)
        }
        .onDisappear {
            WindowManager.shared.setTitlebarDimmed(false)
        }
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
            Text("Все тексты в этой папке будут безвозвратно удалены.")
        }
        .confirmationDialog(
            "Удалить текст?",
            isPresented: Binding(
                get: { snippetPendingDeletion != nil },
                set: { if !$0 { snippetPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить текст", role: .destructive) {
                if let snippet = snippetPendingDeletion {
                    deleteSnippet(snippet)
                }
                snippetPendingDeletion = nil
            }
            Button("Отмена", role: .cancel) {
                snippetPendingDeletion = nil
            }
        } message: {
            Text("Этот текст будет безвозвратно удален.")
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
                    .help("Добавить текст (Cmd+N)")
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel("Добавить новый текст")
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
                Label("В этой папке пока нет текстов", systemImage: "doc.text")
            } description: {
                Text("Создайте первый текст для быстрого доступа по хоткею.")
            } actions: {
                Button("Создать текст") {
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
                                snippetPendingDeletion = snippet
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
            if !coordinator.textIO.isAccessibilityGranted() {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Accessibility не разрешен")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Button("Исправить...") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .help("Открыть Системные настройки для разрешения Accessibility")
                }
            }

            Spacer()

            Button {
                isShowingSettings = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                    Text("Настройки")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(AppTheme.pillRadius)
            }
            .buttonStyle(.plain)
            .help("Настройки приложения и хоткеев (Cmd+,)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func openAccessibilitySettings() {
        coordinator.textIO.promptAccessibilityPermission()
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
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
            }
            .frame(height: 28)
            .onAppear {
                isFolderRenameFocused = true
            }
        } else {
            FolderSidebarRowContent(
                folder: folder,
                isSelected: selectedFolderId == folder.id,
                onRename: {
                    startRenamingFolder(folder)
                },
                onDelete: {
                    folderPendingDeletion = folder
                }
            )
        }
    }

    // MARK: - Inline New Snippet Creator Card

    private func inlineNewSnippetCard(folderId: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Новый текст")
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
                Label("Редактирование текста", systemImage: "pencil")
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
    @State private var isPencilHovered: Bool = false
    @State private var isTrashHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.top, 3)

            Text(snippet.content)
                .font(.system(size: 13))
                .lineLimit(3)
                .truncationMode(.tail)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Actions: Edit and Delete with comfortable 26x26 hit target and Apple-design feedback
            HStack(spacing: 4) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(isPencilHovered ? .primary : .secondary)
                        .frame(width: 26, height: 26)
                        .background(isPencilHovered ? Color.secondary.opacity(0.14) : Color.clear)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isPencilHovered = $0 }
                .help("Редактировать текст на месте")
                .accessibilityLabel("Редактировать текст")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(isTrashHovered ? .red : .red.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .background(isTrashHovered ? Color.red.opacity(0.14) : Color.clear)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isTrashHovered = $0 }
                .help("Удалить текст")
                .accessibilityLabel("Удалить текст")
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

// MARK: - Folder Sidebar Row Content (with hover buttons)

private struct FolderSidebarRowContent: View {
    let folder: FolderWithSnippets
    let isSelected: Bool
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPencilHovered: Bool = false
    @State private var isTrashHovered: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            NavigationLink(value: folder.id) {
                Label(folder.name, systemImage: "folder")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            HStack(spacing: 2) {
                Button(action: onRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(isPencilHovered ? .primary : .secondary)
                        .frame(width: 22, height: 22)
                        .background(isPencilHovered ? Color.secondary.opacity(0.14) : Color.clear)
                        .cornerRadius(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isPencilHovered = $0 }
                .help("Переименовать папку")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(isTrashHovered ? .red : .red.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .background(isTrashHovered ? Color.red.opacity(0.14) : Color.clear)
                        .cornerRadius(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isTrashHovered = $0 }
                .help("Удалить папку...")
            }
            .opacity(isHovered ? 1.0 : 0.0)
            .allowsHitTesting(isHovered)
            .animation(AppTheme.springFast, value: isHovered)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Переименовать...") {
                onRename()
            }
            Divider()
            Button("Удалить папку...", role: .destructive) {
                onDelete()
            }
        }
    }
}
