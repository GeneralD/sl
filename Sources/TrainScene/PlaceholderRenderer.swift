import AppKit
import SLCore

/// Skeleton renderer: a translucent rectangle sliding right-to-left.
/// Proves the overlay mechanics end to end; the SceneKit renderer
/// replaces this behind the same `Renderer` protocol (spike B).
@MainActor
public final class PlaceholderRenderer: Renderer {
    private let train = NSView()
    private let stripWidth: CGFloat
    private let trainSize = CGSize(width: 220, height: 90)

    public let duration: TimeInterval = 8

    public init(spec: RunSpec, stripWidth: CGFloat) {
        self.stripWidth = stripWidth
        train.wantsLayer = true
        train.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        train.layer?.cornerRadius = 8
    }

    public func makeView(in frame: NSRect, spec: RunSpec) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        train.frame = NSRect(origin: .zero, size: trainSize)
        view.addSubview(train)
        return view
    }

    /// Right-to-left like the original: x runs from +width to -trainWidth.
    public func render(at t: TimeInterval) {
        let p = min(max(t / duration, 0), 1)
        let x = stripWidth - (stripWidth + trainSize.width) * p
        train.frame = NSRect(
            x: x, y: 12, width: trainSize.width, height: trainSize.height
        )
    }

    @discardableResult
    public func step(to t: TimeInterval) -> Bool {
        render(at: t)
        return t < duration
    }
}
