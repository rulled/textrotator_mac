import SwiftUI
import AppKit

public enum AppTheme {
    // MARK: - Modern macOS Sequoia / Tahoe Corner Radii
    public static let panelRadius: CGFloat = 20.0
    public static let cardRadius: CGFloat = 12.0
    public static let pillRadius: CGFloat = 8.0
    public static let badgeRadius: CGFloat = 5.0

    // MARK: - Spring Animations (Apple Design Foundations)
    /// Snappy, critically damped spring for instant user interaction and selection
    public static let springFast = Animation.spring(response: 0.25, dampingFraction: 0.82)

    /// Smooth, natural spring for modal transitions and content switching
    public static let springSmooth = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Bouncy spring for micro-interactions with momentum (swap, copy feedback)
    public static let springBouncy = Animation.spring(response: 0.32, dampingFraction: 0.72)

    // MARK: - Liquid Glass Specular Rim Border (Specular Reflection)
    /// Physical rim reflection: top edge catches ambient light (specular highlight),
    /// sides have crisp subpixel definition, bottom edge darkens into window shadow.
    public static func glassSpecularBorder(radius: CGFloat = panelRadius, for colorScheme: ColorScheme) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.30 : 0.55), location: 0.0),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.12 : 0.20), location: 0.12),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.04 : 0.08), location: 0.85),
                        .init(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.12), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
    }

    public static func panelBackgroundStroke(for colorScheme: ColorScheme) -> some View {
        glassSpecularBorder(radius: panelRadius, for: colorScheme)
    }

    // MARK: - Haptic Feedback (Multimodal Harmony)
    public static func hapticClick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    public static func hapticSuccess() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

public extension View {
    @ViewBuilder
    func activeGlassAppearance() -> some View {
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            self.materialActiveAppearance(.active)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func glassButton() -> some View {
        #if compiler(>=6.0)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
        #else
        self.buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    func glassProminentButton() -> some View {
        #if compiler(>=6.0)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
        #else
        self.buttonStyle(.borderedProminent)
        #endif
    }
}
