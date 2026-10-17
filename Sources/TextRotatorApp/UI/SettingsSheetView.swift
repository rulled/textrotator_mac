import SwiftUI
import AppKit
import TextRotatorCore

public struct SettingsSheetView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var isPresented: Bool
    @State private var isAccessibilityGranted: Bool = false
    @State private var recordingAction: HotkeyAction? = nil
    @State private var localKeyMonitor: Any? = nil
    @Environment(\.colorScheme) private var colorScheme

    public init(coordinator: AppCoordinator, isPresented: Binding<Bool>) {
        self.coordinator = coordinator
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 15))

                Text("Настройки")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Закрыть настройки (Escape)")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Section 1: Accessibility
                    accessibilitySection

                    // Section 2: Hotkeys
                    hotkeysSection

                    // Section 3: Translation Provider
                    translationSection
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Готово") {
                    stopRecording()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        }
        .frame(width: 540, height: 480)
        .onAppear {
            refreshAccessibility()
        }
        .onDisappear {
            stopRecording()
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
            return "Text Rotator может напрямую захватывать выделенный текст и вставлять сниппеты в любое приложение без буфера обмена."
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
