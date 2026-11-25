import AppKit
import Foundation

/// Applies `Trajectory` poses to the train's renderer node, one call per
/// frame from the run loop's onFrame with seconds since train-enter.
/// Today the node is the placeholder lane view; the SceneKit renderer
/// swaps in an `SCNNode` behind the same `update(t:)` call.
@MainActor
public final class TrainPresenter {
    public let trajectory: Trajectory
    private weak var node: NSView?

    /// True once the pose reports the train fully past the left edge —
    /// the run loop's exit signal.
    public private(set) var finished = false

    public init(trajectory: Trajectory, node: NSView) {
        self.trajectory = trajectory
        self.node = node
    }

    public func update(t: TimeInterval) {
        let pose = trajectory.pose(at: t)
        finished = pose.finished
        guard let node else { return }
        node.frame = NSRect(
            x: pose.x - trajectory.trainWidth / 2,
            y: pose.y - trajectory.trainHeight / 2,
            width: trajectory.trainWidth,
            height: trajectory.trainHeight
        )
        // `boundsRotation` (degrees) is the AppKit-native tilt — writing
        // the backing layer's affine transform directly is reset by
        // AppKit's layer-geometry sync and never reaches the screen.
        node.boundsRotation = pose.heading * 180 / .pi
    }
}
