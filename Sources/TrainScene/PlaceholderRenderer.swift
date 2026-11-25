import AppKit
import SLCore

/// Skeleton renderer: a translucent rectangle driven by `Trajectory` +
/// `TrainPresenter`. Proves the overlay mechanics end to end; the
/// SceneKit renderer replaces this behind the same `Renderer` protocol
/// (spike B).
@MainActor
public final class PlaceholderRenderer: Renderer {
    private let train = TrainGlyph.makeView()
    private let presenter: TrainPresenter

    public let duration: TimeInterval

    public init(spec: RunSpec, stripWidth: CGFloat) {
        let trajectory = Trajectory(
            laneWidth: Double(stripWidth),
            trainWidth: Double(TrainGlyph.size.width),
            trainHeight: Double(TrainGlyph.size.height),
            duration: 8,
            fly: spec.fly
        )
        duration = trajectory.duration
        presenter = TrainPresenter(trajectory: trajectory, node: train)
    }

    public func makeView(in frame: NSRect, spec: RunSpec) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        train.frame = NSRect(origin: .zero, size: TrainGlyph.size)
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
