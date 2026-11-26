import SceneKit

/// Rolling-stock animation for a rigged steam model: drivers, truck
/// wheelsets and the visible running gear — coupling rods, connecting
/// rods and crossheads. The bundled `loco.usdz` carries named nodes
/// (`driver_*`, `wheelset_*`, `coupling_rod_*`, `connecting_rod_*`,
/// `crosshead_*`) whose pivots sit at their geometry centers, so each
/// part is driven by writing its transform directly.
///
/// Coordinate note: inside `steam_locomotive` local space the axle
/// axis is +x (mapped to world +z after the model-content yaw), the
/// longitudinal axis is y (mapped to world +x, so −y points toward
/// the front of travel) and z is up. All kinematics below are
/// derived in that space. The export's rest pose quarters the cranks
/// 90° apart (right leads), which pins the crank radius:
/// |rod.pivot − driver2.axle| = r_c·√2/2.
///
/// `advance(distance:)` consumes distance in scene units, so the wheels
/// always roll exactly as fast as the train translates — `--scale`,
/// `-l` and `-w` compose for free.
@MainActor
public final class ModelWheelwork {
    private struct Wheel {
        let node: SCNNode
        let sceneRadius: Float
    }
    private struct CrankSide {
        let couplingRod: SCNNode
        let crosshead: SCNNode
        let connectingRod: SCNNode
        var restRodPosition: SCNVector3
        var restCrossPosition: SCNVector3
        let rodOrigin: SCNVector3   // connecting-rod pivot in crosshead space
        let restPinOffset: SCNVector3 // crank-pin pos - crosshead pos, rest
        var restAngle: Float        // crank angle at the export pose
    }
    private var wheels: [Wheel] = []
    private var sides: [CrankSide] = []
    private var crankRadius: Float = 0
    private var driverCenter = SCNVector3Zero // driven crank axle, local
    private var distance: Float = 0
    private var driverSceneRadius: Float = 0

    /// Builds the rig under `root` (the `model-loco` wrapper or its
    /// `model-content` child). Missing names leave the corresponding
    /// part out — a model without a rig simply animates nothing.
    public init(root: SCNNode) {
        func node(_ name: String) -> SCNNode? {
            root.childNode(withName: name, recursively: true)
        }
        for name in ["driver_1", "driver_2", "driver_3",
                     "wheelset_1", "wheelset_2", "wheelset_3"] {
            guard let wheel = node(name) else { continue }
            let b = wheel.boundingBox
            let localRadius = Float((b.max.y - b.min.y) / 2)
            // Wheels sit inside the scaled wrapper; world-space radius
            // keeps the roll tied to screen distance. The scale is
            // uniform, so any basis column's length gives the factor.
            let m = wheel.simdWorldTransform
            let s = simd_length(simd_float3(m.columns.0.x, m.columns.0.y,
                                            m.columns.0.z))
            wheels.append(Wheel(node: wheel,
                                sceneRadius: localRadius * Float(s)))
        }
        // The connecting rod pins onto the middle driver on this rig.
        guard let crankAxle = node("driver_2") else { return }
        driverCenter = crankAxle.position
        driverSceneRadius = wheels.first { $0.node === crankAxle }?
            .sceneRadius ?? 0
        for side in ["L", "R"] {
            guard let rod = node("coupling_rod_\(side)"),
                  let head = node("crosshead_\(side)"),
                  let conrod = node("connecting_rod_\(side)")
            else { continue }
            // Crank radius + rest angle from the rod pivot's offset to
            // the driven axle, in the loco's y-z plane. Local y maps
            // to world +x and z to world +y, so the world crank angle
            // is atan2(dz, dy).
            let dy = Float(rod.position.y - driverCenter.y)
            let dz = Float(rod.position.z - driverCenter.z)
            let r = sqrt(dy * dy + dz * dz)
            crankRadius = max(crankRadius, r)
            sides.append(CrankSide(
                couplingRod: rod, crosshead: head, connectingRod: conrod,
                restRodPosition: rod.position,
                restCrossPosition: head.position,
                rodOrigin: conrod.position,
                restPinOffset: SCNVector3(
                    rod.position.x - head.position.x,
                    rod.position.y - head.position.y,
                    rod.position.z - head.position.z),
                restAngle: atan2(dz, dy)))
        }
    }

    /// Total distance rolled in scene units — `nil` when no rig nodes
    /// were found (plain models animate nothing).
    public var engaged: Bool { !wheels.isEmpty }

    /// Accumulates forward distance and writes every animated node's
    /// transform. `additional` is the distance rolled since the last
    /// call; sign follows travel (positive while crossing).
    public func advance(by additional: Float) {
        distance += additional
        for wheel in wheels where wheel.sceneRadius > 0 {
            // Local +x maps to world +z, so a left-rolling wheel
            // (world +z positive) is a positive local-x rotation.
            let angle = distance / wheel.sceneRadius
            setRotation(wheel.node, angle)
        }
        guard driverSceneRadius > 0, crankRadius > 0 else { return }
        let phase = distance / driverSceneRadius
        for i in sides.indices {
            let θ = sides[i].restAngle + phase
            let (c, s) = (crankRadius * cos(θ), crankRadius * sin(θ))
            let rest = sides[i].restAngle
            let dc = c - crankRadius * cos(rest)
            let ds = s - crankRadius * sin(rest)
            // Coupling rod: rigid rod on the crank circle — every point
            // traces the same orbit; the rod itself never rotates.
            sides[i].couplingRod.position = SCNVector3(
                sides[i].restRodPosition.x,
                sides[i].restRodPosition.y + CGFloat(dc),
                sides[i].restRodPosition.z + CGFloat(ds))
            // Crosshead slides longitudinally with the crank's x
            // projection (long-rod approximation of the slide-bar
            // arc); local +y maps to world +x.
            sides[i].crosshead.position = SCNVector3(
                sides[i].restCrossPosition.x,
                sides[i].restCrossPosition.y + CGFloat(dc),
                sides[i].restCrossPosition.z)
            // Connecting rod: rear end rides the crosshead pin, front
            // end tracks the crank pin — aim it in the y-z plane. The
            // pin rides on the rod's own wheel plane (lateral x), not
            // the axle centerline.
            let pin = SCNVector3(
                sides[i].restRodPosition.x,
                driverCenter.y + CGFloat(c),
                driverCenter.z + CGFloat(s))
            let headPos = sides[i].crosshead.position
            let v = SCNVector3(
                pin.x - headPos.x - sides[i].rodOrigin.x,
                pin.y - headPos.y - sides[i].rodOrigin.y,
                pin.z - headPos.z - sides[i].rodOrigin.z)
            let v0 = SCNVector3(
                sides[i].restPinOffset.x - sides[i].rodOrigin.x,
                sides[i].restPinOffset.y - sides[i].rodOrigin.y,
                sides[i].restPinOffset.z - sides[i].rodOrigin.z)
            sides[i].connectingRod.rotation = SCNVector4(
                x: 1, y: 0, z: 0,
                w: CGFloat(rotationInYZ(from: v0, to: v)))
        }
    }

    /// `SCNNode.rotation` is axis-angle — (x,y,z) axis, w radians —
    /// not a quaternion. The axle axis is local +x (↔ world lateral).
    private func setRotation(_ node: SCNNode, _ angle: Float) {
        node.rotation = SCNVector4(x: 1, y: 0, z: 0, w: CGFloat(angle))
    }

    /// Signed angle rotating `a` onto `b` in the loco's y-z plane —
    /// a single rotation about the +x (lateral) axis.
    private func rotationInYZ(from a: SCNVector3, to b: SCNVector3) -> Float {
        let ay = Float(a.y), az = Float(a.z)
        let by = Float(b.y), bz = Float(b.z)
        return atan2(ay * bz - az * by, ay * by + az * bz)
    }
}
