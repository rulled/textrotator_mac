import SwiftUI
import AppKit
import TextRotatorCore

public struct UpdateModalView: View {
    @ObservedObject var updater = UpdateService.shared
    let info: UpdateInfo
    @Environment(\.colorScheme) private var colorScheme

    public init(info: UpdateInfo) {
        self.info = info
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()
                .opacity(0.15)

            // Content: Scrollable Markdown Release Notes
            changelogView
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            Divider()
                .opacity(0.15)

            // Footer: Progress Indicator or Action Buttons
            footerView
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
        }
        .frame(width: 520, height: 440)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            AppTheme.glassSpecularBorder(radius: AppTheme.panelRadius, for: colorScheme)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.20), radius: 24, x: 0, y: 12)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Доступно обновление TextRotator")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text("Текущая: \(info.currentVersion.description)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    Text("Новая: \(info.version.description)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(AppTheme.badgeRadius)
                }
            }

            Spacer()
        }
    }

    // MARK: - Changelog

    private var changelogView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(info.releaseNotes))
                    .font(.system(size: 12.5))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(AppTheme.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerView: some View {
        switch updater.state {
        case .downloading(let progress, let bytes, let total):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Загрузка обновления...")
                        .font(.system(size: 12, weight: .medium))

                    Spacer()

                    let bytesMB = Double(bytes) / 1_048_576.0
                    let totalMB = Double(total) / 1_048_576.0
                    Text(String(format: "%.1f МБ из %.1f МБ (%.0f%%)", bytesMB, totalMB, progress * 100))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geo.size.width * progress, 8), height: 8)
                            .animation(AppTheme.springFast, value: progress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Spacer()
                    Button("Отмена") {
                        updater.cancelDownload()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
            }

        case .extracting:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Проверка целостности и подготовка к установке...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }

        case .readyToRelaunch:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Обновление готово! Перезапуск приложения...")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
            }

        case .failed(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Повторить") {
                    updater.downloadAndInstall(info: info)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

        default:
            HStack(spacing: 12) {
                Button("Пропустить эту версию") {
                    AppTheme.hapticClick()
                    updater.skipVersion(info.version)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

                Spacer()

                Button("Напомнить позже") {
                    AppTheme.hapticClick()
                    updater.remindLater()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    AppTheme.hapticClick()
                    updater.downloadAndInstall(info: info)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Обновить сейчас")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundColor(.white)
                    .background(Color.accentColor)
                    .cornerRadius(AppTheme.pillRadius)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
