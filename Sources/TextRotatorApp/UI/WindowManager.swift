import Foundation
import AppKit
import SwiftUI

@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()

    private var managerWindow: NSWindow?
    private var titlebarScrim: NSView?

    /// Shows or hides a translucent scrim covering the titlebar so modal overlays
    /// (settings sheet) visually dim the header together with the content.
    /// The native NSTitlebarContainerView renders ABOVE the SwiftUI hosting view,
    /// so a SwiftUI .overlay can never darken it — we add an NSView inside it.
    ///
    /// The scrim is created once per window and toggled via `isHidden`:
    /// adding/removing subviews inside the system-managed titlebar forces the
    /// window server to rebuild the titlebar's blur render graph, which shows up
    /// as a single white frame (visible in light theme). A property flip on an
    /// existing layer composites in-frame with no rebuild.
    public func setTitlebarDimmed(_ dimmed: Bool) {
        guard let window = managerWindow else { return }

        if titlebarScrim == nil {
            installTitlebarScrim(in: window)
        }
        // Re-adopt if the titlebar container was rebuilt (fullscreen, toolbar changes)
        if let scrim = titlebarScrim, scrim.superview == nil {
            scrim.removeFromSuperview()
            titlebarScrim = nil
            installTitlebarScrim(in: window)
        }
        guard let scrim = titlebarScrim else { return }

        if dimmed {
            scrim.isHidden = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.20
                ctx.allowsImplicitAnimation = true
                scrim.animator().alphaValue = 1.0
            }
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                scrim.animator().alphaValue = 0.0
            }, completionHandler: { [weak scrim] in
                if scrim?.alphaValue == 0.0 {
                    scrim?.isHidden = true
                }
            })
        }
    }

    /// Locates NSTitlebarContainerView by walking up from the close button and
    /// installs a pre-created, hidden scrim sized to the container's bounds.
    private func installTitlebarScrim(in window: NSWindow) {
        // Note: two superviews from the close button land on NSTitlebarContainerView
        // (button -> NSTitlebarView -> NSTitlebarContainerView -> NSThemeFrame).
        // Walk by class name so the chain survives internal hierarchy tweaks.
        var candidate = window.standardWindowButton(.closeButton)?.superview
        var container: NSView?
        while let view = candidate {
            if String(describing: type(of: view)).contains("TitlebarContainer") {
                container = view
                break
            }
            candidate = view.superview
        }
        guard let container else { return }

        let scrim = NSView(frame: container.bounds)
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        scrim.autoresizingMask = [.width, .height]
        scrim.alphaValue = 0.0
        scrim.isHidden = true
        // Above title widgets (title text + traffic lights) — topmost in container.
        container.addSubview(scrim, positioned: .above, relativeTo: nil)
        titlebarScrim = scrim
    }

    public func openManagerWindow(coordinator: AppCoordinator) {
        if let existing = managerWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 880, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Text Rotator"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 780, height: 480)
        window.delegate = self
        window.isReleasedWhenClosed = false

        let contentView = SnippetsManagerView(coordinator: coordinator)
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        self.managerWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        managerWindow = nil
        titlebarScrim = nil
    }
}
