import SwiftUI
import AppKit
import TextRotatorCore

public struct TranslatorCardView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var copiedFeedback: Bool = false

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header: Languages & Provider Switcher
            HStack(spacing: 8) {
                // Source language badge
                Text(coordinator.translatorSourceLang.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)

                // Swap button
                Button {
                    swapLanguages()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // Target language badge
                Text(coordinator.translatorTargetLang.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)

                Spacer()

                // Provider Switcher Menu
                Menu {
                    Button("Yandex Translate (Быстрый)") {
                        switchProvider(to: "Yandex")
                    }
                    Button("Google Translate (Резервный)") {
                        switchProvider(to: "Google")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(coordinator.activeProviderName == "Yandex" ? Color.red : Color.blue)
                            .frame(width: 6, height: 6)
                        Text(coordinator.activeProviderName)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Close Button
                Button {
                    coordinator.translatorPanel?.close()
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

            // Source Text Box (Compact)
            if !coordinator.translatorSourceText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(coordinator.translatorSourceText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.3))

                Divider()
            }

            // Translation Output Area
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if coordinator.isTranslating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Перевод...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                    } else {
                        Text(coordinator.translatorResultText.isEmpty ? "Выделите текст для перевода" : coordinator.translatorResultText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(coordinator.translatorResultText.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer Actions
            HStack(spacing: 8) {
                // Copy Action
                Button {
                    copyTranslation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copiedFeedback ? "Скопировано" : "Копировать")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(coordinator.translatorResultText.isEmpty)

                Spacer()

                // Insert In-Place Action
                Button {
                    coordinator.insertCurrentTranslation()
                } label: {
                    HStack(spacing: 4) {
                        Text("↵ Вставить в приложение")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(coordinator.translatorResultText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 420, height: 260)
        .background(.regularMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .onKeyPress { keyPress in
            if keyPress.key == .return {
                coordinator.insertCurrentTranslation()
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

    private func swapLanguages() {
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

        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copiedFeedback = false
        }
    }
}
