import Foundation
import AppKit
import SwiftUI

public final class CustomNonActivatingPanel: NSPanel {
    override public var canBecomeKey: Bool {
        return true
    }

    override public var canBecomeMain: Bool {
        return false
    }

    override public func cancelOperation(_ sender: Any?) {
        self.orderOut(sender)
    }
}

@MainActor
public final class FloatingPanelController: NSObject, NSWindowDelegate {
    public let panel: CustomNonActivatingPanel
    public var isVisible: Bool { panel.isVisible }

    public init(title: String = "") {
        panel = CustomNonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = title
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.animationBehavior = .utilityWindow
    }

    public func setContent<Content: View>(view: Content, size: NSSize) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.setContentSize(size)
    }

    public func positionNearCursor(size: NSSize, offsetX: CGFloat = 12, offsetY: CGFloat = 14) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens[0]

        let visibleFrame = targetScreen.visibleFrame

        // Default: display slightly to the right and below the cursor
        var x = mouseLocation.x + offsetX
        var y = mouseLocation.y - size.height - offsetY

        // Bounds constraints: ensure it stays within the visible screen area
        if x + size.width > visibleFrame.maxX {
            x = mouseLocation.x - size.width - offsetX
        }
        if x < visibleFrame.minX {
            x = visibleFrame.minX + 8
        }

        if y < visibleFrame.minY {
            y = mouseLocation.y + offsetY
        }
        if y + size.height > visibleFrame.maxY {
            y = visibleFrame.maxY - size.height - 8
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    public func show() {
        panel.alphaValue = 0.0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
    }

    public func close() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1.0
            }
        }
    }
    public func windowDidResignKey(_ notification: Notification) {
        // Auto-close on blur if needed
        close()
    }
}
