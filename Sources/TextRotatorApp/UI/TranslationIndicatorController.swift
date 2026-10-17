import Foundation
import AppKit
import SwiftUI

public enum IndicatorState: Sendable, Equatable {
    case spinning
    case checkmark
    case cross
}

/// Ultra-lightweight non-activating circular HUD panel displayed near cursor during F1 in-place translation
/// or on/off feedback for cursor translate mode.
@MainActor
public final class TranslationIndicatorController: NSObject {
    private let panel: NSPanel
    private var isVisible: Bool = false

    public override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 34, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: IndicatorContentView(state: .spinning))
        hostingView.frame = NSRect(x: 0, y: 0, width: 34, height: 34)
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: 34, height: 34))
    }

    public func showNearCursor(
        state: IndicatorState = .spinning,
        offset: NSPoint = NSPoint(x: 14, y: -18),
        autoDismissDelay: Double? = nil
    ) {
        let hostingView = NSHostingView(rootView: IndicatorContentView(state: state))
        hostingView.frame = NSRect(x: 0, y: 0, width: 34, height: 34)
        panel.contentView = hostingView

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens[0]

        let visibleFrame = targetScreen.visibleFrame
        var x = mouseLocation.x + offset.x
        var y = mouseLocation.y + offset.y

        if x + 34 > visibleFrame.maxX {
            x = mouseLocation.x - 34 - offset.x
        }
        if y < visibleFrame.minY {
            y = mouseLocation.y - offset.y
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        isVisible = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        if let delay = autoDismissDelay {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self.dismiss()
            }
        }
    }

    public func dismiss() {
        guard isVisible else { return }
        isVisible = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }) { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1.0
            }
        }
    }
}

// MARK: - SwiftUI Indicator View

private struct IndicatorContentView: View {
    let state: IndicatorState
    @State private var isSpinning: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .activeGlassAppearance()
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.18)
                                : Color.black.opacity(0.12),
                            lineWidth: 0.5
                        )
                )

            switch state {
            case .spinning:
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.accentColor.opacity(0.2),
                                Color.accentColor
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 0.75)
                            .repeatForever(autoreverses: false),
                        value: isSpinning
                    )
                    .onAppear {
                        isSpinning = true
                    }

            case .checkmark:
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.green)

            case .cross:
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.red)
            }
        }
        .frame(width: 34, height: 34)
    }
}
