import SwiftUI
import AppKit
import TextRotatorCore

public struct TranslatorCardView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var copiedFeedback: Bool = false
    @State private var swapRotation: Double = 0.0

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header: Languages, Swap & Provider
            HStack(spacing: 8) {
                // Source language badge
                Text(coordinator.translatorSourceLang.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14))
                    .cornerRadius(AppTheme.badgeRadius)

                // Animated Swap Button
                Button {
                    swapLanguages()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(swapRotation))
                }
                .buttonStyle(.plain)
                .help("Поменять языки местами")
                .accessibilityLabel("Сменить направление перевода")

                // Target language badge
                Text(coordinator.translatorTargetLang.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.2))
                    .foregroundColor(.accentColor)
                    .cornerRadius(AppTheme.badgeRadius)

                Spacer()

                // Provider Switcher Menu with Latency Badge
                Menu {
                    Button("Yandex Translate (Быстрый)") {
                        switchProvider(to: "Yandex")
                    }
                    Button("Google Translate (Резервный)") {
                        switchProvider(to: "Google")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(coordinator.activeProviderName == "Yandex" ? Color.red : Color.blue)
                            .frame(width: 6, height: 6)

                        Text(coordinator.activeProviderName)
                            .font(.system(size: 11, weight: .medium))

                        if let latency = coordinator.lastLatencyMs {
                            Text("• \(latency)ms")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(AppTheme.pillRadius)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Выбор сервиса перевода")

                // Close Button
                Button {
                    coordinator.translatorPanel?.close()
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
                .help("Закрыть окно (Escape)")
                .accessibilityLabel("Закрыть")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            // Non-blocking Pulse Progress Indicator under header
            if coordinator.isTranslating {
                LinearProgressPulse()
                    .frame(height: 2)
            } else {
                Divider()
            }

            // MARK: - Source Text Box (Compact preview)
            if !coordinator.translatorSourceText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.translatorSourceText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
                .help(coordinator.translatorSourceText)

                Divider()
            }

            // MARK: - Translation Result Text Area
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if coordinator.translatorResultText.isEmpty && !coordinator.isTranslating {
                        Text("Выделите текст в любом приложении для перевода")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    } else {
                        Text(coordinator.translatorResultText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // MARK: - Footer Actions
            HStack(spacing: 8) {
                // Copy Action Button
                Button {
                    copyTranslation()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(copiedFeedback ? .green : .primary)
                        Text(copiedFeedback ? "Скопировано" : "Копировать")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(AppTheme.pillRadius)
                }
                .buttonStyle(SpringFeedbackButtonStyle())
                .disabled(coordinator.translatorResultText.isEmpty)
                .help("Скопировать перевод в буфер обмена (Cmd+C)")
                .accessibilityLabel("Скопировать перевод")

                Spacer()

                // In-Place Insert Action Button
                Button {
                    insertTranslation()
                } label: {
                    HStack(spacing: 5) {
                        Text("↵ Вставить в приложение")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.pillRadius)
                }
                .buttonStyle(SpringFeedbackButtonStyle())
                .disabled(coordinator.translatorResultText.isEmpty)
                .help("Заменить выделенный текст переводом (Enter)")
                .accessibilityLabel("Вставить перевод в активное приложение")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 420, height: 260)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .overlay(AppTheme.panelBackgroundStroke(for: colorScheme))
        .onKeyPress { keyPress in
            if keyPress.key == .return {
                insertTranslation()
                return .handled
            }
            if keyPress.key == .escape {
                coordinator.translatorPanel?.close()
                coordinator.restoreForegroundApp()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Actions

    private func swapLanguages() {
        withAnimation(AppTheme.springBouncy) {
            swapRotation += 180.0
        }
        AppTheme.hapticClick()

        let temp = coordinator.translatorSourceLang
        coordinator.translatorSourceLang = coordinator.translatorTargetLang
        coordinator.translatorTargetLang = temp

        if !coordinator.translatorResultText.isEmpty {
            let nextSource = coordinator.translatorResultText
            coordinator.translatorSourceText = nextSource
            Task {
                await coordinator.requestTranslation(text: nextSource)
            }
        }
    }

    private func switchProvider(to providerName: String) {
        coordinator.activeProviderName = providerName
        AppTheme.hapticClick()

        if !coordinator.translatorSourceText.isEmpty {
            Task {
                await coordinator.requestTranslation(
                    text: coordinator.translatorSourceText,
                    preferredProvider: providerName
                )
            }
        }
    }

    private func copyTranslation() {
        guard !coordinator.translatorResultText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(coordinator.translatorResultText, forType: .string)

        AppTheme.hapticSuccess()
        withAnimation(AppTheme.springFast) {
            copiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(AppTheme.springFast) {
                copiedFeedback = false
            }
        }
    }

    private func insertTranslation() {
        AppTheme.hapticSuccess()
        coordinator.insertCurrentTranslation()
    }
}

// MARK: - Linear Progress Pulse Bar

private struct LinearProgressPulse: View {
    @State private var phase: CGFloat = 0.0

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.2),
                            Color.accentColor,
                            Color.accentColor.opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: proxy.size.width * 0.4)
                .offset(x: phase * proxy.size.width * 0.7)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        phase = 1.0
                    }
                }
        }
        .clipped()
    }
}

private struct SpringFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppTheme.springFast, value: configuration.isPressed)
    }
}
