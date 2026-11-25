import Foundation

/// The stretch of lane the Dock occupies, in lane-local x points
/// (right-to-left travel: `maxX` is the entry edge, `minX` the exit).
/// Pure value type — detection lives in `OverlayGeometry`, the hop
/// math in `Trajectory`.
public struct DockZone: Equatable, Sendable {
    public var minX: Double
    public var maxX: Double
    /// Parabola apex above the lane, in points.
    public var apex: Double
    /// Peak pitch delta added to the pose heading, in radians.
    public var tilt: Double

    public init(minX: Double, maxX: Double, apex: Double = 40,
                tilt: Double = 0.15) {
        precondition(maxX > minX, "dock zone must span positive width")
        precondition(apex >= 0)
        self.minX = minX
        self.maxX = maxX
        self.apex = apex
        self.tilt = tilt
    }

    /// Whether the train center `x` is inside the zone.
    public func contains(_ x: Double) -> Bool {
        x >= minX && x <= maxX
    }

    /// Progress through the zone: 0 at the right (entry) edge, 1 at the
    /// left (exit) edge. Clamped so edge poses land exactly on the lane.
    public func progress(atX x: Double) -> Double {
        min(max((maxX - x) / (maxX - minX), 0), 1)
    }

    /// Parabolic lift: 0 at both edges, `apex` at the zone center.
    public func lift(atX x: Double) -> Double {
        let u = progress(atX: x)
        return apex * 4 * u * (1 - u)
    }

    /// Pitch delta for the pose heading: negative (nose-up) while the
    /// train climbs the first half, positive (nose-down) while it comes
    /// back down — the hop reads as a jump, not a drift.
    public func pitch(atX x: Double) -> Double {
        tilt * (2 * progress(atX: x) - 1)
    }
}
