import SwiftUI
import AppKit
import TextRotatorCore

public struct SettingsSheetView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var isPresented: Bool
    @State private var isAccessibilityGranted: Bool = false
    @State private var recordingAction: HotkeyAction? = nil
    @State private var localKeyMonitor: Any? = nil
    @State private var isCloseHovered: Bool = false
    @State private var isImportPickerPresented: Bool = false
    @State private var configMessage: String? = nil
    @State private var configMessageIsError: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var updater = UpdateService.shared

    public init(coordinator: AppCoordinator, isPresented: Binding<Bool>) {
        self.coordinator = coordinator
        self._isPresented = isPresented
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                accessibilitySection
                hotkeysSection
                translationSection
                configSection
                updatesSection
            }
            .padding(24)
        }
        .frame(width: 520, height: 460)
        .overlay(alignment: .topTrailing) {
            Button {
                stopRecording()
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isCloseHovered ? .primary : .secondary)
                    .frame(width: 26, height: 26)
                    .background(Color(NSColor.windowBackgroundColor).opacity(isCloseHovered ? 0.95 : 0.80))
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .padding(.top, 14)
            .padding(.trailing, 16)
            .zIndex(100)
            .help("Закрыть настройки (Escape)")
            .accessibilityLabel("Закрыть настройки")
        }
        .onAppear {
            refreshAccessibility()
        }
        .onDisappear {
            stopRecording()
        }
        .onKeyPress { keyPress in
            if keyPress.key == .escape {
                stopRecording()
                isPresented = false
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Section 1: Accessibility

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Универсальный доступ (Accessibility)", systemImage: "hand.raised.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            accessibilityCard
        }
    }

    private var accessibilityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isAccessibilityGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(isAccessibilityGranted ? .green : .orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(isAccessibilityGranted ? "Доступ предоставлен" : "Требуется разрешение macOS")
                    .font(.system(size: 13, weight: .semibold))

                Text(accessibilityDescriptionText)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)

                accessibilityActionButtons
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(AppTheme.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(
                    isAccessibilityGranted ? Color.green.opacity(0.25) : Color.orange.opacity(0.35),
                    lineWidth: 1
                )
        )
    }

    private var accessibilityDescriptionText: String {
        if isAccessibilityGranted {
            return "Text Rotator может напрямую захватывать выделенный текст и вставлять тексты в любое приложение без буфера обмена."
        } else {
            return "macOS требует доступ к Универсальному доступу. Нажмите кнопку, откройте раздел настроек и включите тумблер напротив Text Rotator."
        }
    }

    private var accessibilityActionButtons: some View {
        HStack(spacing: 10) {
            if isAccessibilityGranted {
                Button {
                    openSystemAccessibilitySettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Системные настройки...")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    openSystemAccessibilitySettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Открыть Настройки macOS...")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button("Проверить статус") {
                refreshAccessibility()
                AppTheme.hapticClick()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Section 2: Hotkeys

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Горячие клавиши (Глобальные хоткеи)", systemImage: "keyboard.fill")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Button("По умолчанию") {
                    coordinator.resetHotkeysToDefault()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .help("Сбросить все комбинации клавиш по умолчанию (F1-F4)")
            }

            VStack(spacing: 8) {
                hotkeyRow(
                    action: .quickSnippetsOverlay,
                    title: "Быстрые шаблоны (Quick Snippets)",
                    description: "Всплывающий оверлей с папками и текстами у курсора"
                )

                Divider()

                hotkeyRow(
                    action: .instantTranslateAndReplace,
                    title: "Мгновенный перевод по месту",
                    description: "Перевод выделенного текста с микро-индикатором"
                )

                Divider()

                hotkeyRow(
                    action: .translatorOverlay,
                    title: "Оверлей переводчика",
                    description: "Плавающая карточка со сменой языка и провайдера"
                )

                Divider()

                hotkeyRow(
                    action: .cursorTranslateToggle,
                    title: "Автоперевод выделения мыши",
                    description: "Всплытие карточки перевода сразу при отпускании мыши",
                    isToggle: true
                )
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(AppTheme.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    private func hotkeyRow(
        action: HotkeyAction,
        title: String,
        description: String,
        isToggle: Bool = false
    ) -> some View {
        let isRecording = (recordingAction == action)
        let combo = coordinator.currentKeyCombo(for: action)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))

                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isToggle {
                Toggle("", isOn: Binding(
                    get: { coordinator.isCursorTranslateEnabled },
                    set: { _ in coordinator.toggleCursorTranslateMode() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording(action: action)
                }
            } label: {
                if isRecording {
                    Text("Нажмите клавиши...")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(AppTheme.badgeRadius)
                } else {
                    Text(combo.displayString)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(AppTheme.badgeRadius)
                }
            }
            .buttonStyle(.plain)
            .help("Нажмите, чтобы записать новую комбинацию клавиш (Esc для отмены)")
        }
        .padding(.vertical, 2)
    }

    private func startRecording(action: HotkeyAction) {
        AppTheme.hapticClick()
        recordingAction = action
        stopLocalMonitor()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            var mods: KeyModifiers = []
            if event.modifierFlags.contains(.command) { mods.insert(.command) }
            if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
            if event.modifierFlags.contains(.option) { mods.insert(.option) }
            if event.modifierFlags.contains(.control) { mods.insert(.control) }

            let combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            coordinator.updateHotkey(for: action, combo: combo)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recordingAction = nil
        stopLocalMonitor()
    }

    private func stopLocalMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - Section 3: Translation

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Движок перевода", systemImage: "globe")
                .font(.system(size: 13, weight: .bold))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Основной провайдер перевода")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Yandex работает быстрее (~100мс), Google используется как надежный резерв.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("", selection: $coordinator.activeProviderName) {
                    Text("Yandex Translate (Быстрый)").tag("Yandex")
                    Text("Google Translate (Резервный)").tag("Google")
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(AppTheme.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Config Import / Export Section

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Импорт и экспорт конфигурации", systemImage: "externaldrive.fill.badge.arrow.up.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Резервная копия")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Полная совместимость с оригинальным TextRotator для Windows: папки, тексты, горячие клавиши и настройки.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        exportConfig()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Экспорт")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Сохранить бэкап в файл JSON")

                    Button {
                        isImportPickerPresented = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Импорт")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Загрузить бэкап из файла JSON (заменит текущие папки)")
                }

                if let message = configMessage {
                    HStack(spacing: 6) {
                        Image(systemName: configMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(configMessageIsError ? .orange : .green)
                        Text(message)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(AppTheme.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
        }
        .fileImporter(
            isPresented: $isImportPickerPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importConfig(from: url)
                }
            case .failure(let error):
                setConfigMessage("Ошибка выбора файла: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func exportConfig() {
        do {
            let data = try coordinator.exportConfiguration()

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "text_rotator_backup.json"
            panel.message = "Резервная копия TextRotator"
            panel.canCreateDirectories = true

            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url, options: .atomic)
                let folders = coordinator.folders
                let snippetCount = folders.reduce(0) { $0 + $1.snippets.count }
                setConfigMessage("Экспортировано: \(folders.count) папок, \(snippetCount) текстов → \(url.lastPathComponent)", isError: false)
                AppTheme.hapticSuccess()
            }
        } catch {
            setConfigMessage("Ошибка экспорта: \(error.localizedDescription)", isError: true)
        }
    }

    private func importConfig(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let result = try coordinator.importConfiguration(data: data, replaceExisting: true)
            setConfigMessage(
                "Импортировано: \(result.foldersImported) папок, \(result.snippetsImported) текстов, \(result.hotkeysImported) хоткеев, \(result.settingsImported) настроек",
                isError: false
            )
            AppTheme.hapticSuccess()
        } catch {
            setConfigMessage("Ошибка импорта: \(error.localizedDescription)", isError: true)
        }
    }

    private func setConfigMessage(_ text: String, isError: Bool) {
        withAnimation(AppTheme.springFast) {
            configMessage = text
            configMessageIsError = isError
        }
    }

    // MARK: - Updates Section

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Обновление программы", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("TextRotator")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("v\(updater.currentAppVersion.description)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(AppTheme.badgeRadius)
                        }
                        Text("Проверка свежих релизов и обновлений с GitHub.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        updater.checkForUpdates(isUserInitiated: true)
                    } label: {
                        HStack(spacing: 5) {
                            if updater.state == .checking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(updater.state == .checking ? "Проверка..." : "Проверить сейчас")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updater.state == .checking)
                }

                Divider()
                    .opacity(0.12)

                Toggle(isOn: $updater.isAutomaticCheckEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Автоматически проверять обновления")
                            .font(.system(size: 12, weight: .medium))
                        Text("Фоновая тихая проверка релизов при старте приложения.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(AppTheme.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Helpers

    private func refreshAccessibility() {
        isAccessibilityGranted = coordinator.textIO.isAccessibilityGranted()
    }

    private func openSystemAccessibilitySettings() {
        // Prompt system check dialog if needed
        coordinator.textIO.promptAccessibilityPermission()

        // Raycast-style direct deep-link to Privacy & Security -> Accessibility
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
