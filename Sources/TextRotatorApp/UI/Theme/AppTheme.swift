import SwiftUI
import AppKit

public enum AppTheme {
    // MARK: - Corner Radii
    public static let panelRadius: CGFloat = 14.0
    public static let cardRadius: CGFloat = 10.0
    public static let pillRadius: CGFloat = 6.0
    public static let badgeRadius: CGFloat = 4.0

    // MARK: - Spring Animations (Apple Design Foundations)
    /// Snappy, critically damped spring for instant user interaction and selection
    public static let springFast = Animation.spring(response: 0.25, dampingFraction: 0.82)

    /// Smooth, natural spring for modal transitions and content switching
    public static let springSmooth = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Bouncy spring for micro-interactions with momentum (swap, copy feedback)
    public static let springBouncy = Animation.spring(response: 0.32, dampingFraction: 0.72)

    // MARK: - Light-Catching Hairline Borders
    public static func hairlineBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.08)
    }

    public static func panelBackgroundStroke(for colorScheme: ColorScheme) -> some View {
        RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
            .stroke(hairlineBorder(for: colorScheme), lineWidth: 0.5)
    }

    // MARK: - Haptic Feedback (Multimodal Harmony)
    public static func hapticClick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    public static func hapticSuccess() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
