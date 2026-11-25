import SceneKit

/// Drives the procedural locomotive's running gear from distance
/// traveled, never wall-clock: each `wheel-*` pivot turns at angular
/// velocity `speedPx / radius` (issue #21), and the `rod-*` connecting
/// rods reciprocate on the driver crank radius — in-phase crank pins,
/// so the rods translate vertically without tilting, like the real
/// coupling rod. Node trees without the hooks (a `--model` scene) make
/// it a no-op.
@MainActor
public final class WheelworkAnimator {
    /// Crank-pin radius as a fraction of the driver wheel radius.
    private static let crankRatio: CGFloat = 0.45

    private struct Wheel {
        let node: SCNNode
        /// Rolling radius in scene units, read off the wheel mesh.
        let radius: CGFloat
    }

    private var wheels: [Wheel] = []
    private var rods: [(node: SCNNode, restY: CGFloat)] = []
    /// Driver axle radius — the crank the rods reciprocate against.
    private var driveRadius: CGFloat = 0

    public init(train: SCNNode) {
        collectWheels(in: train)
        collectRods(in: train)
        driveRadius = wheels.first { $0.node.name == "wheel-driver-1" }?.radius
            ?? wheels.map(\.radius).max() ?? 0
    }

    /// `distance` is scene units traveled since train-enter (the
    /// trajectory is linear, so this is `speed * t` exactly).
    public func update(distance: CGFloat) {
        for wheel in wheels {
            wheel.node.eulerAngles.z = distance / wheel.radius
        }
        guard driveRadius > 0 else { return }
        let offset = driveRadius * Self.crankRatio
            * sin(distance / driveRadius)
        for rod in rods {
            rod.node.position.y = rod.restY + offset
        }
    }

    private func collectWheels(in node: SCNNode) {
        if let name = node.name, name.hasPrefix("wheel-"),
           !name.hasSuffix("-mesh"), !name.hasSuffix("-spoke"),
           let radius = wheelRadius(of: node) {
            wheels.append(Wheel(node: node, radius: radius))
        }
        node.childNodes.forEach(collectWheels(in:))
    }

    private func collectRods(in node: SCNNode) {
        if let name = node.name, name == "rod-drive" || name == "rod-coupling" {
            rods.append((node, node.position.y))
        }
        node.childNodes.forEach(collectRods(in:))
    }

    /// The wheel pivot's mesh child is a z-axis `SCNCylinder`; its
    /// `radius` is already in scene units (scale applied at build).
    private func wheelRadius(of pivot: SCNNode) -> CGFloat? {
        pivot.childNodes.lazy
            .compactMap { $0.geometry as? SCNCylinder }
            .first?.radius
    }
}
