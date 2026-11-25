import AppKit
import OverlayKit
import SLCore

/// Skeleton renderer: a translucent rectangle driven by `Trajectory` +
/// `TrainPresenter`. Proves the overlay mechanics end to end; the
/// SceneKit renderer replaces this behind the same `Renderer` protocol
/// (spike B).
@MainActor
public final class PlaceholderRenderer: Renderer {
    private let train = TrainGlyph.makeView()
    private let presenter: TrainPresenter
    /// The glyph's on-screen size — the design glyph scaled by the
    /// lane ratio and `--scale`, keeping its old lane fraction.
    private let glyphSize: CGSize

    public let duration: TimeInterval

    public init(spec: RunSpec, stripWidth: CGFloat,
                dock: [DockZone] = [],
                laneHeight: CGFloat = OverlayGeometry.referenceLaneHeight) {
        precondition(laneHeight > 0)
        let userScale = spec.scale.isFinite && spec.scale > 0
            ? spec.scale : 1
        let s = laneHeight / OverlayGeometry.referenceLaneHeight
            * CGFloat(userScale)
        glyphSize = CGSize(width: TrainGlyph.size.width * s,
                           height: TrainGlyph.size.height * s)
        let trajectory = Trajectory(
            laneWidth: Double(stripWidth),
            trainWidth: Double(glyphSize.width),
            trainHeight: Double(glyphSize.height),
            duration: 8,
            fly: spec.fly,
            dock: dock
        )
        duration = trajectory.duration
        presenter = TrainPresenter(trajectory: trajectory, node: train)
    }

    public func makeView(in frame: NSRect, spec: RunSpec) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        train.frame = NSRect(origin: .zero, size: glyphSize)
        view.addSubview(train)
        return view
    }

    /// Right-to-left like the original: `Trajectory` owns the math.
    public func render(at t: TimeInterval) {
        presenter.update(t: t)
    }

    @discardableResult
    public func step(to t: TimeInterval) -> Bool {
        render(at: t)
        return !presenter.finished
    }
}
