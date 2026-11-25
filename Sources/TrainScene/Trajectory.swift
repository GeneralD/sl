import Foundation
import SLCore

/// One instant of the train's crossing, in lane points — the ortho
/// scene space the SceneKit camera exposes (foreshortened by the 3/4
/// tilt, see docs/adr/scene.md). `x`/`y` are the train's center; `heading` is the
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
///
/// `dock` zones add a hop on top of the level lane run: while the train
/// center crosses a zone its y lifts on a parabola and the heading
/// pitches nose-up then nose-down. The hop never applies to `fly`.
public struct Trajectory: Sendable {
    /// Lane width in points; the train travels from `laneWidth + margin`
    /// past the right edge to `-margin` past the left edge.
    public var laneWidth: Double
    public var trainWidth: Double
    public var trainHeight: Double
    /// Off-screen padding on both ends and the bottom inset.
    public var margin: Double
    /// Wall-clock seconds for one full crossing.
    public var duration: TimeInterval
    /// `-F` flight: climb the `y = x/7` diagonal instead of holding the
    /// lane's bottom edge.
    public var fly: Bool
    /// Dock zones the level run hops over, in lane-local x points.
    /// Empty (or `fly`) means a flat lane run.
    public var dock: [DockZone]

    public init(laneWidth: Double, trainWidth: Double, trainHeight: Double,
                margin: Double = 8, duration: TimeInterval,
                fly: Bool = false, dock: [DockZone] = []) {
        precondition(laneWidth > 0 && trainWidth > 0 && trainHeight > 0)
        precondition(margin >= 0)
        precondition(duration > 0)
        self.laneWidth = laneWidth
        self.trainWidth = trainWidth
        self.trainHeight = trainHeight
        self.margin = margin
        self.duration = duration
        self.fly = fly
        self.dock = dock
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
        // `end` is built so the right edge sits exactly at `-margin`
        // at p == 1, but `x + trainWidth/2 <= -margin` is a borderline
        // float compare — arbitrary consist widths (real car lengths)
        // can land an ulp above and `finished` would never flip. The
        // geometric condition is equivalent to reaching the end pose.
        let finished = p >= 1 || x + trainWidth / 2 <= -margin
        guard fly else {
            let laneY = trainHeight / 2 + margin
            guard let zone = dock.first(where: { $0.contains(x) }) else {
                return Pose(x: x, y: laneY, heading: 0, finished: finished)
            }
            return Pose(
                x: x,
                y: laneY + zone.lift(atX: x),
                heading: zone.pitch(atX: x),
                finished: finished
            )
        }
        return Pose(
            x: x,
            y: (laneWidth - x) / 7 + trainHeight / 2,
            heading: -atan(1.0 / 7.0),
            finished: finished
        )
    }
}
