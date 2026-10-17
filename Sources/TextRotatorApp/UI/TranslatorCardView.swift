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
                        .rotationEffect(.degrees(swapRotation))
                }
                .glassButton()
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            // Non-blocking Pulse Progress Indicator under header
            if coordinator.isTranslating {
                LinearProgressPulse()
                    .frame(height: 2)
            } else {
                Divider()
            }

            // MARK: - Translation Result Area (Pure Translation Output)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if coordinator.translatorResultText.isEmpty && !coordinator.isTranslating {
                        Text("Выделите текст для перевода")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    } else {
                        Text(coordinator.translatorResultText)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(.primary)
                            .lineSpacing(3.5)
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
                }
                .glassButton()
                .disabled(coordinator.translatorResultText.isEmpty)
                .help("Скопировать перевод (Cmd+C)")
                .accessibilityLabel("Скопировать перевод")

                Spacer()

                // In-Place Insert Action Button
                Button {
                    insertTranslation()
                } label: {
                    Text("↵ Вставить в приложение")
                        .font(.system(size: 11, weight: .semibold))
                }
                .glassProminentButton()
                .disabled(coordinator.translatorResultText.isEmpty)
                .help("Заменить выделенный текст переводом (Enter)")
                .accessibilityLabel("Вставить перевод в активное приложение")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 380, height: 210)
        .background(.ultraThinMaterial)
        .activeGlassAppearance()
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .overlay(AppTheme.glassSpecularBorder(for: colorScheme))
        .onKeyPress { keyPress in
            if keyPress.key == .return {
                insertTranslation()
                return .handled
            } else if keyPress.key == .escape {
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
            coordinator.translatorResultText = ""
            Task {
                await coordinator.requestTranslation(text: nextSource)
            }
        }
    }

    private func switchProvider(to providerName: String) {
        guard providerName != coordinator.activeProviderName else { return }
        AppTheme.hapticClick()
        coordinator.activeProviderName = providerName

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
        AppTheme.hapticSuccess()

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(coordinator.translatorResultText, forType: .string)

        withAnimation(AppTheme.springFast) {
            copiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(AppTheme.springFast) {
                self.copiedFeedback = false
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
            let width = proxy.size.width
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.accentColor.opacity(0.85),
                            Color.accentColor,
                            Color.accentColor.opacity(0.85),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 0.4, height: 2)
                .offset(x: -width * 0.4 + phase * (width * 1.4))
        }
        .clipped()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1.0
            }
        }
    }
}

private struct SpringFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(AppTheme.springFast, value: configuration.isPressed)
    }
}
