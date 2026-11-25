import Foundation

/// Fixed-dt clock for animation/timing logic. Checks step the world by
/// explicit deltas — nothing ever sleeps or reads wall time.
public struct Tick {
    public private(set) var t: TimeInterval

    public init(start: TimeInterval = 0) {
        t = start
    }

    @discardableResult
    public mutating func step(dt: TimeInterval) -> TimeInterval {
        t += dt
        return t
    }

    /// Step until `t` reaches `limit` or `body` returns false. Bounded so
    /// a broken "running" state can't spin forever.
    public mutating func advance(until limit: TimeInterval, dt: TimeInterval = 1.0 / 60,
                                 while body: (TimeInterval) -> Bool) -> TimeInterval {
        while t < limit, body(t) { _ = step(dt: dt) }
        return t
    }
}
