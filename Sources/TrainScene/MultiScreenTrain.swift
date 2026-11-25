import AppKit
import OverlayKit
import SLCore

/// The placeholder train glyph — one styling source for the
/// single-display renderer and the multi-display stage until the
/// SceneKit renderer lands behind the same seam.
public enum TrainGlyph {
    public static let size = CGSize(width: 220, height: 90)

    @MainActor
    public static func makeView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        view.layer?.cornerRadius = 8
        return view
    }
}

/// `--all`: one train crossing every display. A single global-space
/// `Trajectory` produces the pose; each attached node lives in its
/// screen's lane window, gets the global pose mapped to screen-local
/// coordinates, and is hidden when the train doesn't intersect that
/// display's strip.
@MainActor
public final class MultiScreenTrain {
    public let trajectory: Trajectory
    /// The global lane rect (AppKit screen coordinates) that the
    /// trajectory's lane-local pose is offset by.
    public let lane: NSRect

    /// True once the pose reports the train fully past the left edge —
    /// the run loop's exit signal.
    public private(set) var finished = false

    private var screens: [(frame: NSRect, node: NSView)] = []

    /// `scale` is the `--scale` factor; the glyph also grows with the
    /// lane ratio so `--all` keeps its lane fraction on tall strips.
    public init(lane: NSRect, duration: TimeInterval = 8, fly: Bool = false,
                dock: [DockZone] = [], scale: CGFloat = 1) {
        self.lane = lane
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let s = lane.height / OverlayGeometry.referenceLaneHeight * safeScale
        let glyph = CGSize(width: TrainGlyph.size.width * s,
                           height: TrainGlyph.size.height * s)
        trajectory = Trajectory(
            laneWidth: Double(lane.width),
            trainWidth: Double(glyph.width),
            trainHeight: Double(glyph.height),
            duration: duration,
            fly: fly,
            dock: dock
        )
    }

    public var duration: TimeInterval { trajectory.duration }

    /// Attach one display: `frame` is the screen's global frame, `node`
    /// the train view inside that screen's lane window.
    public func attach(screenFrame frame: NSRect, node: NSView) {
        node.isHidden = true
        screens.append((frame, node))
    }

    /// Advance to `t` seconds since train-enter and reposition every
    /// attached node.
    public func update(t: TimeInterval) {
        let pose = trajectory.pose(at: t)
        finished = pose.finished
        let train = NSRect(
            x: lane.minX + pose.x - trajectory.trainWidth / 2,
            y: lane.minY + pose.y - trajectory.trainHeight / 2,
            width: trajectory.trainWidth,
            height: trajectory.trainHeight
        )
        for screen in screens {
            screen.node.isHidden = !OverlayGeometry.showsTrain(
                train, onScreenFrame: screen.frame, laneHeight: lane.height)
            screen.node.frame = OverlayGeometry.localRect(
                train, onScreenFrame: screen.frame)
            screen.node.boundsRotation = pose.heading * 180 / .pi
        }
    }
}
