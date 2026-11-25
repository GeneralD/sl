import AppKit
import SLCore

/// A borderless, transparent, click-through window floating above all
/// normal UI — Dock, menu bar, and fullscreen Spaces — on every Space.
/// Recipe verified against shipping overlays (see PRODUCT.md → Exemplars).
public final class OverlayWindow: NSWindow {
    public init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// `--stealth`: `.none` excludes the window from screen capture;
    /// `.readOnly` is AppKit's default share level.
    public func setStealth(_ enabled: Bool) {
        sharingType = enabled ? .none : .readOnly
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
