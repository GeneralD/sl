import AppKit
import SceneKit

/// The paint scheme slot behind `-c`: `d51` is the default JNR
/// black, `c51` the `-c` red-edged variant, `variant` the reserved
/// slot for future liveries (disco, …). `-G` does not use this enum —
/// the TGV gets its own node builder (`ProceduralTGV`). Colors are
/// diffuse-only — the lighting rig in `SceneKitRenderer` does the rest.
public enum Livery: String, Sendable, CaseIterable {
    case d51
    case c51
    case variant
}

/// The bundled locomotive: a D51-ish steam engine built entirely from
/// SceneKit primitives — boiler, cab, chimney, steam dome, sand dome,
/// cowcatcher, running board, six wheels, drive/coupling rods and a
/// tender. Polycount is trivial by design (docs/adr/scene.md).
///
/// `node` is the whole train as one `SCNNode` whose pivot sits at track
/// contact: the bounding box's bottom is y = 0 and it is centered on x,
/// so `SceneKitRenderer` positions it like the old placeholder box.
/// Named children (`boiler`, `wheel-driver-1`, `rod-drive`, …) are the
/// animation hooks — wheels are pivots at axle height with the mesh in
/// a pre-rotated child, ready for `.repeatForever` spin.
public struct ProceduralLocomotive {
    /// Lane-space footprint at `scale == 1`: ~154 pt tall (cab roof
    /// included), ~340 pt wide.
    public static let size = CGSize(width: 340, height: 154)

    public let node: SCNNode

    /// - Parameters:
    ///   - livery: paint scheme (`-c` selects `.c51`; `-G` never
    ///     reaches this builder — see `ProceduralTGV`).
    ///   - scale: `-l` miniature factor; 1 is lane height.
    public init(livery: Livery = .d51, scale: CGFloat = 1) {
        precondition(scale > 0)
        node = Self.build(livery: livery, scale: scale)
    }

    // MARK: - Layout (unit = points at scale 1, front is -x)

    /// Boiler: a tapered cone primitive, axis rotated onto x — narrow
    /// smokebox at the front (-x), full girth at the cab end. The taper
    /// is what the 3/4 camera finally gets to show off.
    private static func boiler(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("boiler",
             SCNCone(topRadius: 20 * s, bottomRadius: 24 * s,
                     height: 168 * s),
             at: (-52 * s, 56 * s, 0),
             eulerZ: .pi / 2,
             material: m.body)
    }

    /// Cab: the tall box at the rear (+x), roof line at y = 150.
    private static func cab(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("cab",
             SCNBox(width: 46 * s, height: 120 * s, length: 48 * s,
                    chamferRadius: 2 * s),
             at: (52 * s, 90 * s, 0),
             material: m.body)
    }

    /// Cab roof: a thin slab overhanging the cab box — the top face
    /// the elevated camera reads as "roof" instead of a bare edge.
    private static func cabRoof(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("cab-roof",
             SCNBox(width: 52 * s, height: 4 * s, length: 54 * s,
                    chamferRadius: 1 * s),
             at: (52 * s, 152 * s, 0),
             material: m.trim)
    }

    /// Chimney: vertical cylinder on the boiler's front shoulder.
    private static func chimney(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("chimney",
             SCNCylinder(radius: 7 * s, height: 36 * s),
             at: (-118 * s, 96 * s, 0),
             material: m.trim)
    }

    /// Chimney cap: a flared rim disc crowning the smokestack.
    private static func chimneyCap(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("chimney-cap",
             SCNCylinder(radius: 9 * s, height: 3 * s),
             at: (-118 * s, 115.5 * s, 0),
             material: m.dark)
    }

    private static func steamDome(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("steam-dome",
             SCNSphere(radius: 13 * s),
             at: (-76 * s, 88 * s, 0),
             material: m.trim)
    }

    /// Dome skirt: a short cylinder collar the sphere sits in, so the
    /// dome reads as mounted on the boiler crown instead of floating.
    private static func steamDomeBase(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("steam-dome-base",
             SCNCylinder(radius: 12.5 * s, height: 6 * s),
             at: (-76 * s, 76 * s, 0),
             material: m.trim)
    }

    private static func sandDome(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("sand-dome",
             SCNSphere(radius: 10 * s),
             at: (-100 * s, 85 * s, 0),
             material: m.trim)
    }

    private static func sandDomeBase(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("sand-dome-base",
             SCNCylinder(radius: 9.5 * s, height: 6 * s),
             at: (-100 * s, 74 * s, 0),
             material: m.trim)
    }

    /// Cowcatcher: a wedge of a box sloping down toward the front (-x).
    private static func cowcatcher(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("cowcatcher",
             SCNBox(width: 36 * s, height: 8 * s, length: 44 * s,
                    chamferRadius: 1 * s),
             at: (-158 * s, 16 * s, 0),
             eulerZ: 0.5,
             material: m.accent)
    }

    /// Running board: the long side plank at frame height.
    private static func runningBoard(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("running-board",
             SCNBox(width: 220 * s, height: 5 * s, length: 52 * s,
                    chamferRadius: 1 * s),
             at: (-50 * s, 39 * s, 0),
             material: m.dark)
    }

    /// Tender: the coal/water box behind the cab — darker than the
    /// boiler so the two masses don't fuse into one slab.
    private static func tender(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("tender",
             SCNBox(width: 92 * s, height: 48 * s, length: 48 * s,
                    chamferRadius: 2 * s),
             at: (120 * s, 54 * s, 0),
             material: m.dark)
    }

    /// Cab windows: two pale panes proud of the cab's +z face, each
    /// backed by a slightly larger dark frame slab so a border reads
    /// around the glass, plus a center mullion joining them.
    private static func cabWindows(_ m: Materials, s: CGFloat) -> [SCNNode] {
        let panes = [(-8, "cab-window-1"), (8, "cab-window-2")].map { dx, name in
            prim(name,
                 SCNBox(width: 14 * s, height: 26 * s, length: 1.5 * s,
                        chamferRadius: 0.5 * s),
                 at: ((52 + dx) * s, 112 * s, 24.5 * s),
                 material: m.window)
        }
        let frames = [(-8, "window-frame-1"), (8, "window-frame-2")].map { dx, name in
            prim(name,
                 SCNBox(width: 17 * s, height: 29 * s, length: 1 * s,
                        chamferRadius: 0.5 * s),
                 at: ((52 + dx) * s, 112 * s, 24 * s),
                 material: m.dark)
        }
        let mullion = prim("cab-mullion",
                           SCNBox(width: 2 * s, height: 26 * s, length: 1.6 * s,
                                  chamferRadius: 0.3 * s),
                           at: (52 * s, 112 * s, 24.4 * s),
                           material: m.dark)
        return panes + frames + [mullion]
    }

    /// Headlight: small brass sphere on the cab's front top corner.
    private static func headlight(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("headlight",
             SCNSphere(radius: 5 * s),
             at: (28 * s, 128 * s, 0),
             material: m.trim)
    }

    /// One wheel: the named node is the animation pivot at axle height;
    /// its children carry the cylinder pre-rotated so the axle runs
    /// along z (the rolling direction is a z-rotation of the parent)
    /// plus a brass spoke bar — a plain cylinder is rotationally
    /// symmetric, so without the spoke the spin is invisible.
    private static func wheel(_ name: String, x: CGFloat, radius: CGFloat,
                              s: CGFloat, material: SCNMaterial,
                              spoke: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        node.name = name
        node.position = SCNVector3(Float(x * s), Float(radius * s), 0)
        let mesh = SCNNode(
            geometry: SCNCylinder(radius: radius * s, height: 14 * s))
        mesh.name = "\(name)-mesh"
        mesh.eulerAngles.x = .pi / 2 // cylinder y-axis -> z-axis
        mesh.geometry?.materials = [material]
        node.addChildNode(mesh)
        let bar = SCNNode(geometry: SCNBox(
            width: radius * 1.8 * s, height: 3 * s, length: 2 * s,
            chamferRadius: 0))
        // Named without the `wheel-` prefix so hook scans that match
        // `wheel-*` pivots don't pick the spoke up as a wheel.
        bar.name = "spoke-\(name)"
        bar.geometry?.materials = [spoke]
        node.addChildNode(bar)
        return node
    }

    private static func wheels(_ m: Materials, s: CGFloat) -> [SCNNode] {
        [
            wheel("wheel-leading", x: -140, radius: 14, s: s,
                  material: m.wheel, spoke: m.trim),
            wheel("wheel-driver-1", x: -112, radius: 20, s: s,
                  material: m.wheel, spoke: m.trim),
            wheel("wheel-driver-2", x: -72, radius: 20, s: s,
                  material: m.wheel, spoke: m.trim),
            wheel("wheel-driver-3", x: -32, radius: 20, s: s,
                  material: m.wheel, spoke: m.trim),
            wheel("wheel-driver-4", x: 8, radius: 20, s: s,
                  material: m.wheel, spoke: m.trim),
            wheel("wheel-trailing", x: 52, radius: 16, s: s,
                  material: m.wheel, spoke: m.trim),
        ]
    }

    /// Handrails: a thin rod running the boiler flank on each side —
    /// the classic steam-loco walkway rail. On the tapered boiler a
    /// straight rail can't hug the surface everywhere, so it floats a
    /// couple of points proud at the narrow end and bites in at the
    /// wide end; at this scale it still reads as railing.
    private static func handrails(_ m: Materials, s: CGFloat) -> [SCNNode] {
        [1.0, -1.0].enumerated().map { i, side in
            prim("handrail-\(i + 1)",
                 SCNCylinder(radius: 1.1 * s, height: 150 * s),
                 at: (-52 * s, 45 * s, 19.5 * s * side),
                 eulerZ: .pi / 2,
                 material: m.trim)
        }
    }

    /// Pipe hints: a vertical steam-pipe drop beside the sand dome and
    /// a longitudinal pipe along the boiler crown feeding the
    /// chimney. Silhouette-only — no bends at this scale.
    private static func pipes(_ m: Materials, s: CGFloat) -> [SCNNode] {
        [
            prim("steam-pipe",
                 SCNCylinder(radius: 1.6 * s, height: 16 * s),
                 at: (-88 * s, 80 * s, 10 * s),
                 material: m.dark),
            prim("sandbox-pipe",
                 SCNBox(width: 44 * s, height: 2.2 * s, length: 2.2 * s,
                        chamferRadius: 0.4 * s),
                 at: (-106 * s, 78.5 * s, 5 * s),
                 material: m.dark),
        ]
    }

    /// Drive rod: thin box joining the driver crank pins — the future
    /// `SCNAction` target along with the wheel pivots.
    private static func driveRod(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("rod-drive",
             SCNBox(width: 128 * s, height: 5 * s, length: 5 * s,
                    chamferRadius: 0.5 * s),
             at: (-52 * s, 30 * s, 10 * s),
             material: m.rod)
    }

    /// Coupling rod: the lower rod tying all six wheels together.
    private static func couplingRod(_ m: Materials, s: CGFloat) -> SCNNode {
        prim("rod-coupling",
             SCNBox(width: 196 * s, height: 4 * s, length: 4 * s,
                    chamferRadius: 0.5 * s),
             at: (-44 * s, 24 * s, -10 * s),
             material: m.rod)
    }

    // MARK: - Assembly

    private static func build(livery: Livery, scale s: CGFloat) -> SCNNode {
        let m = Materials(livery)
        let root = SCNNode()
        root.name = "procedural-locomotive"

        // `body` lets us re-center horizontally and pin the pivot to
        // track contact (bbox min.y == 0) regardless of layout drift.
        let body = SCNNode()
        body.name = "body"
        for part in [cowcatcher(m, s: s), boiler(m, s: s), cab(m, s: s),
                     cabRoof(m, s: s), chimney(m, s: s),
                     chimneyCap(m, s: s), steamDome(m, s: s),
                     steamDomeBase(m, s: s), sandDome(m, s: s),
                     sandDomeBase(m, s: s), runningBoard(m, s: s),
                     tender(m, s: s), headlight(m, s: s),
                     driveRod(m, s: s), couplingRod(m, s: s)]
            + cabWindows(m, s: s) + handrails(m, s: s)
            + pipes(m, s: s) + wheels(m, s: s) {
            body.addChildNode(part)
        }
        root.addChildNode(body)

        let bounds = body.boundingBox
        body.position = SCNVector3(
            -(bounds.min.x + bounds.max.x) / 2, -bounds.min.y, 0)
        return root
    }

    // MARK: - Primitives

    /// A named node holding one primitive, centered on `at`, optionally
    /// rotated about z (the boiler's axis trick).
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
        let body: SCNMaterial
        let trim: SCNMaterial
        let accent: SCNMaterial
        let dark: SCNMaterial
        let wheel: SCNMaterial
        let rod: SCNMaterial
        let window: SCNMaterial

        init(_ livery: Livery) {
            /// Physically-based paint/metal: `metalness`/`roughness`
            /// do the tuning `diffuse` alone can't — brass domes and
            /// rods catch the key light, paint stays satin.
            func pbr(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                     metalness: CGFloat, roughness: CGFloat) -> SCNMaterial {
                let m = SCNMaterial()
                m.lightingModel = .physicallyBased
                m.diffuse.contents = NSColor(
                    calibratedRed: r, green: g, blue: b, alpha: 1)
                m.metalness.contents = NSNumber(value: Double(metalness))
                m.roughness.contents = NSNumber(value: Double(roughness))
                return m
            }
            // JNR palette: D51 black, C51 vermilion edged in black
            // trim, variant navy (reserved slot).
            let bodyRGB: (CGFloat, CGFloat, CGFloat) = switch livery {
            case .d51: (0.11, 0.11, 0.12)
            case .c51: (0.62, 0.13, 0.07)
            case .variant: (0.09, 0.16, 0.36)
            }
            body = pbr(bodyRGB.0, bodyRGB.1, bodyRGB.2,
                       metalness: 0.25, roughness: 0.55)
            // C51's red is edged by black trim — domes, chimney and
            // headlight go charcoal instead of brass.
            let edged = livery == .c51
            trim = pbr(edged ? 0.10 : 0.55,
                       edged ? 0.10 : 0.42,
                       edged ? 0.11 : 0.16,
                       metalness: edged ? 0.3 : 0.85,
                       roughness: edged ? 0.5 : 0.32)
            accent = pbr(0.42, 0.09, 0.07, // cowcatcher red
                         metalness: 0.3, roughness: 0.5)
            dark = pbr(0.16, 0.16, 0.17,
                       metalness: 0.6, roughness: 0.5)
            wheel = pbr(0.09, 0.09, 0.10,
                        metalness: 0.9, roughness: 0.38)
            rod = pbr(0.45, 0.46, 0.48,    // steel rods
                      metalness: 0.95, roughness: 0.3)
            window = pbr(0.62, 0.72, 0.78, // pale cab glass
                         metalness: 0.1, roughness: 0.08)
        }
    }
}
