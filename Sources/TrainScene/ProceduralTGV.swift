import AppKit
import SceneKit

/// The `-G` variant: a TGV-style power car built from primitives — a
/// long low body, a rounded bullet nose, a dark window band, two bogies
/// with spinning wheels and a yellow stripe. Same contract as
/// `ProceduralLocomotive`: one `SCNNode`, pivot at track contact
/// (bbox min.y == 0), centered on x, named `wheel-*` hooks so
/// `WheelworkAnimator` spins the bogie wheels for free.
public struct ProceduralTGV {
    /// Lane-space footprint at `scale == 1`: ~120 pt tall, ~430 pt wide.
    public static let size = CGSize(width: 430, height: 120)

    public let node: SCNNode

    /// - Parameters:
    ///   - scale: `-l` miniature factor; 1 is lane height.
    public init(scale: CGFloat = 1) {
        precondition(scale > 0)
        node = Self.build(scale: scale)
    }

    // MARK: - Layout (unit = points at scale 1, front is -x)

    /// Lower body: the long slab everything else sits on.
    private static func lowerBody(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("tgv-body",
             SCNBox(width: 380 * s, height: 52 * s, length: 78 * s,
                    chamferRadius: 8 * s),
             at: (-10 * s, 62 * s, 0),
             material: m.body)
    }

    /// Upper body: a slimmer slab on top, inset fore-aft.
    private static func upperBody(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("tgv-cabin",
             SCNBox(width: 340 * s, height: 34 * s, length: 70 * s,
                    chamferRadius: 8 * s),
             at: (-10 * s, 104 * s, 0),
             material: m.body)
    }

    /// Bullet nose: a cone rotated onto the x axis, apex forward — the
    /// cheapest wedge that reads as a streamlined cab.
    private static func nose(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("tgv-nose",
             SCNCone(topRadius: 6 * s, bottomRadius: 39 * s,
                     height: 74 * s),
             at: (-206 * s, 72 * s, 0),
             eulerZ: .pi / 2,
             material: m.body)
    }

    /// Window band: a dark ribbon proud of both sides of the cabin.
    private static func windowBand(_ m: Materials, s: CGFloat) -> [SCNNode] {
        [1.0, -1.0].map { side in
            prim("tgv-window-\(side > 0 ? "near" : "far")",
                 SCNBox(width: 300 * s, height: 16 * s, length: 2 * s,
                        chamferRadius: 0.5 * s),
                 at: (-14 * s, 106 * s, side * 36 * s),
                 material: m.window)
        }
    }

    /// Livery stripe: the TGV's signature band along the lower flank.
    private static func stripe(_ m: Materials, s: CGFloat) -> [SCNNode] {
        [1.0, -1.0].map { side in
            prim("tgv-stripe-\(side > 0 ? "near" : "far")",
                 SCNBox(width: 360 * s, height: 8 * s, length: 1 * s,
                        chamferRadius: 0.5 * s),
                 at: (-10 * s, 52 * s, side * 40 * s),
                 material: m.stripe)
        }
    }

    /// Roof fairing: a thin slab softening the cabin top.
    private static func roof(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("tgv-roof",
             SCNBox(width: 320 * s, height: 6 * s, length: 64 * s,
                    chamferRadius: 3 * s),
             at: (-10 * s, 124 * s, 0),
             material: m.dark)
    }

    /// Bogie: dark underframe box plus two wheel pivots per bogie —
    /// same `wheel-*`/z-axis-cylinder contract as the steam loco, so
    /// `WheelworkAnimator` spins them with no extra wiring.
    private static func bogie(_ m: Materials, s: CGFloat,
                              index: Int, x: CGFloat) -> [SCNNode] {
        let frame = prim("tgv-bogie-\(index)",
                         SCNBox(width: 56 * s, height: 14 * s, length: 74 * s,
                                chamferRadius: 2 * s),
                         at: (x * s, 16 * s, 0),
                         material: m.dark)
        return [frame] + [1.0, -1.0].enumerated().map { i, side in
            let name = "wheel-tgv-\(index)-\(i + 1)"
            let pivot = SCNNode()
            pivot.name = name
            pivot.position = SCNVector3(
                Float(x * s), Float(11 * s), Float(side * 32 * s))
            let mesh = SCNNode(
                geometry: SCNCylinder(radius: 11 * s, height: 5 * s))
            mesh.name = "\(name)-mesh"
            mesh.eulerAngles.x = .pi / 2 // cylinder y-axis -> z-axis
            mesh.geometry?.materials = [m.wheel]
            pivot.addChildNode(mesh)
            return pivot
        }
    }

    /// Headlight: a small pale sphere on the nose tip.
    private static func headlight(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("tgv-headlight",
             SCNSphere(radius: 4 * s),
             at: (-238 * s, 76 * s, 0),
             material: m.window)
    }

    // MARK: - Assembly

    private static func build(scale s: CGFloat) -> SCNNode {
        let m = Materials()
        let root = SCNNode()
        root.name = "procedural-tgv"

        // Same pivot contract as the steam loco: bbox min.y == 0,
        // centered on x, so `SceneKitRenderer` positions it identically.
        let body = SCNNode()
        body.name = "body"
        for part in [lowerBody(m, s: s), upperBody(m, s: s),
                     nose(m, s: s), roof(m, s: s), headlight(m, s: s)]
            + windowBand(m, s: s) + stripe(m, s: s)
            + bogie(m, s: s, index: 1, x: -120)
            + bogie(m, s: s, index: 2, x: 110) {
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
                             eulerZ: CGFloat = 0,
                             material: SCNMaterial) -> SCNNode {
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.position = SCNVector3(Float(p.0), Float(p.1), Float(p.2))
        node.eulerAngles.z = eulerZ
        geometry.materials = [material]
        return node
    }

    private struct Materials {
        let body: SCNMaterial   // TGV silver
        let dark: SCNMaterial   // roof, bogies
        let window: SCNMaterial // dark glass band
        let stripe: SCNMaterial // yellow livery band
        let wheel: SCNMaterial  // bogie wheels

        init() {
            func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
                let m = SCNMaterial()
                m.diffuse.contents = NSColor(
                    calibratedRed: r, green: g, blue: b, alpha: 1)
                m.lightingModel = .blinn
                return m
            }
            body = color(0.82, 0.84, 0.86)
            dark = color(0.16, 0.17, 0.18)
            window = color(0.08, 0.10, 0.13)
            stripe = color(0.85, 0.55, 0.05)
            wheel = color(0.09, 0.09, 0.10)
        }
    }
}
