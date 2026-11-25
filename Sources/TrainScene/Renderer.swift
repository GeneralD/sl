import AppKit
import SLCore

/// The seam that keeps the 3D implementation swappable — SceneKit is the
/// current implementation; an MTKView or ARView swap touches this file's
/// callers nowhere. `sl` and `OverlayKit` never name SceneKit.
/// Every renderer is UI-bound: the protocol itself is `@MainActor`.
@MainActor
public protocol Renderer {
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
}
