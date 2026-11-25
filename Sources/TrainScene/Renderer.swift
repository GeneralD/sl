import AppKit
import SLCore

/// The seam that keeps the 3D implementation swappable — SceneKit is the
/// current implementation; an MTKView or ARView swap touches this file's
/// callers nowhere. `sl` and `OverlayKit` never name SceneKit.
/// Every renderer is UI-bound: the protocol itself is `@MainActor`.
@MainActor
public protocol Renderer: Sendable {
    /// The view filling the overlay window's lane.
    func makeView(in frame: NSRect, spec: RunSpec) -> NSView

    /// Total wall-clock seconds of one crossing.
    var duration: TimeInterval { get }

    /// Pin the scene to a fixed point in the run (`scripts/shot` mode).
    /// `t` is seconds from train-enter to train-exit.
    func render(at t: TimeInterval)

    /// Advance one display frame toward `t`; returns true while running.
    @discardableResult
    func step(to t: TimeInterval) -> Bool

    /// Total seconds the scene asks the run loop to hold after the
    /// train exits — the ghost-steam trail dissipating before the
    /// finish fade. 0 for renderers with no post-exit scene.
    var postExitHold: TimeInterval { get }

    /// Post-exit hold still owed at `t` seconds since train-enter;
    /// 0 once the trail has decayed (or the train never finished).
    func postExitRemaining(at t: TimeInterval) -> TimeInterval
}

public extension Renderer {
    var postExitHold: TimeInterval { 0 }
    func postExitRemaining(at t: TimeInterval) -> TimeInterval { 0 }
}
