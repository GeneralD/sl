import AppKit
import SceneKit

/// One trailing car behind the locomotive — a passenger-car/wagon
/// suggestion built from SceneKit primitives under the same pivot
/// convention as `ProceduralLocomotive`: the node's bounding-box
/// bottom is y = 0 (track contact) and the box is centered on x, so a
/// chain of cars drops into the loco's local space without offsets.
///
/// Cars trail toward +x: the train runs right-to-left with the nose
/// at -x, so the consist extends to the right of the tender.
public struct Car {
    /// Lane-space footprint at `scale == 1`.
    public static let size = CGSize(width: 200, height: 92)

    /// Breathing room between a car's rear and the next car's front —
    /// and between the loco's rear edge and the first car.
    public static let couplingGap: CGFloat = 14

    public let node: SCNNode

    /// - Parameter scale: `-l` miniature factor; 1 is lane height.
    public init(scale: CGFloat = 1) {
        precondition(scale > 0)
        node = Self.build(scale: scale)
    }

    /// `n` cars in coupling order — `car-1` nearest the loco — spaced
    /// by `couplingGap`, trailing toward +x. The returned `car-chain`
    /// node's origin sits on the loco's rear edge; the first car's
    /// front is `couplingGap` past it. `n == 0` yields an empty chain.
    public static func cars(n: Int, scale: CGFloat = 1) -> SCNNode {
        precondition(n >= 0)
        let chain = SCNNode()
        chain.name = "car-chain"
        let pitch = (size.width + couplingGap) * scale
        for i in 0..<n {
            let car = Car(scale: scale).node
            car.name = "car-\(i + 1)"
            car.position = SCNVector3(
                Float(couplingGap * scale + size.width * scale / 2
                      + CGFloat(i) * pitch), 0, 0)
            chain.addChildNode(car)
        }
        return chain
    }

    /// Scene units the chain adds behind the loco's rear edge — what
    /// `Trajectory` adds to the consist width so the last car fully
    /// exits before the run reports finished.
    public static func chainLength(n: Int, scale: CGFloat = 1) -> CGFloat {
        CGFloat(max(n, 0)) * (size.width + couplingGap) * scale
    }

    // MARK: - Layout (unit = points at scale 1, front is -x)

    /// Roof: a low slab over the body, slightly wider so the eaves
    /// read against the sky-less overlay.
    private static func roof(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("car-roof",
             SCNBox(width: 186 * s, height: 9 * s, length: 47 * s,
                    chamferRadius: 1.5 * s),
             at: (0, 73 * s, 0),
             material: m.roof)
    }

    /// Side wall: the main box between floor and eaves.
    private static func wall(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("car-body",
             SCNBox(width: 176 * s, height: 47 * s, length: 43 * s,
                    chamferRadius: 2 * s),
             at: (0, 43.5 * s, 0),
             material: m.body)
    }

    /// Window band: one pale strip per flank — the cheapest trick
    /// that makes the car read as a passenger car.
    private static func windows(_ m: Materials, s: CGFloat) -> [SCNNode] {
        [1.0, -1.0].map { side in
            prim("car-windows",
                 SCNBox(width: 158 * s, height: 13 * s, length: 1.5 * s,
                        chamferRadius: 0.5 * s),
                 at: (0, 50 * s, 22 * side * s),
                 material: m.window)
        }
    }

    /// Bogies: the dark trucks the wheels hang under, one per end.
    private static func bogies(_ m: Materials, s: CGFloat) -> [SCNNode] {
        [-58, 58].map { x in
            prim("car-bogie",
                 SCNBox(width: 42 * s, height: 13 * s, length: 38 * s,
                        chamferRadius: 1.5 * s),
                 at: (CGFloat(x) * s, 16 * s, 0),
                 material: m.dark)
        }
    }

    /// Couplers: short links at floor height on both ends — adjacent
    /// cars' couplers nearly touch across `couplingGap`.
    private static func couplers(_ m: Materials, s: CGFloat) -> [SCNNode] {
        [-1.0, 1.0].map { dir in
            prim("car-coupler",
                 SCNBox(width: 9 * s, height: 8 * s, length: 8 * s,
                        chamferRadius: 1 * s),
                 at: (dir * 89 * s, 11 * s, 0),
                 material: m.dark)
        }
    }

    /// One wheel: named `wheel-car-*` so `WheelworkAnimator` picks it
    /// up — same pivot-at-axle pattern as the loco's wheels, with a
    /// spoke bar so the spin is visible.
    private static func wheel(_ name: String, x: CGFloat,
                              s: CGFloat, material: SCNMaterial,
                              spoke: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        node.name = name
        node.position = SCNVector3(Float(x * s), Float(10 * s), 0)
        let mesh = SCNNode(
            geometry: SCNCylinder(radius: 10 * s, height: 10 * s))
        mesh.name = "\(name)-mesh"
        mesh.eulerAngles.x = .pi / 2 // cylinder y-axis -> z-axis
        mesh.geometry?.materials = [material]
        node.addChildNode(mesh)
        let bar = SCNNode(geometry: SCNBox(
            width: 17 * s, height: 2.5 * s, length: 1.5 * s,
            chamferRadius: 0))
        bar.name = "spoke-\(name)"
        bar.geometry?.materials = [spoke]
        node.addChildNode(bar)
        return node
    }

    private static func wheels(_ m: Materials, s: CGFloat) -> [SCNNode] {
        [-62, -24, 24, 62].enumerated().map { i, x in
            wheel("wheel-car-\(i + 1)", x: x, s: s,
                  material: m.wheel, spoke: m.trim)
        }
    }

    // MARK: - Assembly

    private static func build(scale s: CGFloat) -> SCNNode {
        let m = Materials()
        let root = SCNNode()
        root.name = "passenger-car"

        // `body` lets us re-center horizontally and pin the pivot to
        // track contact (bbox min.y == 0) like the locomotive does.
        let body = SCNNode()
        body.name = "body"
        for part in [roof(m, s: s), wall(m, s: s)] + windows(m, s: s)
            + bogies(m, s: s) + couplers(m, s: s) + wheels(m, s: s) {
            body.addChildNode(part)
        }
        root.addChildNode(body)

        let bounds = body.boundingBox
        body.position = SCNVector3(
            -(bounds.min.x + bounds.max.x) / 2, -bounds.min.y, 0)
        return root
    }

    // MARK: - Primitives

    private static func prim(_ name: String, _ geometry: SCNGeometry,
                             at p: (CGFloat, CGFloat, CGFloat),
                             material: SCNMaterial) -> SCNNode {
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.position = SCNVector3(Float(p.0), Float(p.1), Float(p.2))
        geometry.materials = [material]
        return node
    }

    private struct Materials {
        let body: SCNMaterial
        let roof: SCNMaterial
        let window: SCNMaterial
        let dark: SCNMaterial
        let wheel: SCNMaterial
        let trim: SCNMaterial

        init() {
            func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
                let m = SCNMaterial()
                m.diffuse.contents = NSColor(
                    calibratedRed: r, green: g, blue: b, alpha: 1)
                m.lightingModel = .blinn
                return m
            }
            body = color(0.36, 0.11, 0.09)   // oxblood passenger car
            roof = color(0.18, 0.18, 0.20)
            window = color(0.62, 0.72, 0.78) // pale glass band
            dark = color(0.12, 0.12, 0.13)   // bogies/couplers
            wheel = color(0.08, 0.08, 0.09)
            trim = color(0.50, 0.40, 0.18)   // brass spokes
        }
    }
}
