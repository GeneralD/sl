import Foundation

/// One instant of the train's crossing, in ortho/scene points — the same
/// space the SceneKit camera exposes (scene units == screen points, see
/// docs/adr/scene.md). `x`/`y` are the train's center; `heading` is the
/// rotation applied to the level leftward pose in radians (0 = level,
/// negative tilts the nose up the fly diagonal); `finished` flips once
/// the whole train has passed the left edge plus `margin`.
public struct Pose: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var heading: Double
    public var finished: Bool
}

/// Pure R→L lane math: linear interpolation in pixel space, the same
/// idea as upstream sl.c animating columns per frame. No AppKit, no
/// clock — `pose(at:)` is a pure function of `t`.
///
/// Two modes share the same x(t): the level lane run, and `fly` — the
/// upstream `-F` diagonal `y = x/7` (sl.c computes it in y-down cells;
/// ported here to y-up lane points as center `y = (laneWidth - x)/7 +
/// trainHeight/2`, slope 1/7, exiting toward the upper-left corner).
public struct Trajectory: Sendable {
    /// Lane width in points; the train travels from `laneWidth + margin`
    /// past the right edge to `-margin` past the left edge.
    public var laneWidth: Double
    /// Lane (strip) height in points; read only in `fly` mode, where the
    /// diagonal is measured against the lane's top edge.
    public var laneHeight: Double
    public var trainWidth: Double
    public var trainHeight: Double
    /// Off-screen padding on both ends and the bottom inset.
    public var margin: Double
    /// Wall-clock seconds for one full crossing.
    public var duration: TimeInterval
    /// `-F` flight: climb the `y = x/7` diagonal instead of holding the
    /// lane's bottom edge.
    public var fly: Bool

    public init(laneWidth: Double, trainWidth: Double, trainHeight: Double,
                margin: Double = 8, duration: TimeInterval,
                laneHeight: Double = 0, fly: Bool = false) {
        precondition(laneWidth > 0 && trainWidth > 0 && trainHeight > 0)
        precondition(margin >= 0)
        precondition(duration > 0)
        precondition(!fly || laneHeight > 0)
        self.laneWidth = laneWidth
        self.laneHeight = laneHeight
        self.trainWidth = trainWidth
        self.trainHeight = trainHeight
        self.margin = margin
        self.duration = duration
        self.fly = fly
    }

    /// `t` is seconds since train-enter; values outside `[0, duration]`
    /// clamp to the start/end poses. `finished` is the geometric
    /// condition "train's right edge is left of `-margin`" — in fly
    /// mode the train is already above the lane's top edge by then.
    public func pose(at t: TimeInterval) -> Pose {
        let p = min(max(t / duration, 0), 1)
        let start = laneWidth + margin + trainWidth / 2
        let end = -(margin + trainWidth / 2)
        let x = start + (end - start) * p
        guard fly else {
            return Pose(
                x: x,
                y: trainHeight / 2 + margin,
                heading: 0,
                finished: x + trainWidth / 2 <= -margin
            )
        }
        return Pose(
            x: x,
            y: (laneWidth - x) / 7 + trainHeight / 2,
            heading: -atan(1.0 / 7.0),
            finished: x + trainWidth / 2 <= -margin
        )
    }
}
