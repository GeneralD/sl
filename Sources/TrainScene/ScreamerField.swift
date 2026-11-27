import AppKit
import SceneKit

/// `-a` visual half (issue #37): tiny crowd figures that pop up inside
/// the car windows while the loco rocks. Every pose is a pure function
/// of `t` — no clock, no randomness — so spec checks and `--freeze`
/// shots see the same frame. Scream audio is the audio engine's job
/// (`RunSpec.wantScreams`); this type never touches sound.
///
/// Placement is per-coach: the caller hands each passenger car's
/// bounding box in train space (any pivot convention — the windows
/// stay inside the car), and windows spread inside each car's side
/// band proportional to its size. The loco and tender get none —
/// they carry no passenger windows (earlier the whole-consist band
/// floated a window over the loco nose and starved the last coach).
@MainActor
final class ScreamerField {
    /// Reference loco height the window/figure dimensions scale from.
    private static let referenceHeight: CGFloat = 150

    /// Seconds for one full pop cycle per figure.
    private let period: TimeInterval = 1.15

    /// Attach point: the renderer adds this node to the train.
    let root = SCNNode()
    private var figures: [(node: SCNNode, phase: Double,
                           anchorY: CGFloat, unit: CGFloat)] = []

    /// `cars` — one `(lo, hi)` train-space box per passenger coach.
    init(cars: [(lo: SCNVector3, hi: SCNVector3)]) {
        root.name = "screamers"
        var total = 0
        for car in cars {
            let width = CGFloat(car.hi.x - car.lo.x)
            let height = CGFloat(car.hi.y - car.lo.y)
            let unit = height / Self.referenceHeight
            let spacing = 28 * unit
            // Degenerate boxes (zero-size model) must not reach
            // Int(_:): spacing 0 or non-finite yields NaN.
            guard spacing.isFinite, spacing > 0,
                  width.isFinite, height.isFinite,
                  width > 0, height > 0 else { continue }
            // Window band sits in the body's upper half — the coach
            // model's own openings run ~0.6 of its height.
            let windowY = car.lo.y + height * 0.62
            // The z nudge scales with `unit` like every other
            // dimension: model runs hand us asset-unit bounds
            // (meters), where a fixed 1.5 would hover the windows
            // far off the body.
            let frontZ = car.hi.z + 1.5 * unit
            // Coach ends carry doors and gangways — windows keep a
            // body inset off each end.
            let xLo = car.lo.x + width * 0.07
            let xHi = car.hi.x - width * 0.07
            let count = max(1, min(64 - total, Int((xHi - xLo) / spacing)))
            guard count > 0 else { break }
            let span = CGFloat(count - 1) * spacing
            let startX = (xLo + xHi) / 2 - span / 2
            for i in 0..<count {
                addWindow(
                    at: startX + CGFloat(i) * spacing,
                    y: windowY, frontZ: frontZ,
                    unit: unit, seed: total + i)
            }
            total += count
            if total >= 64 { break }
        }
    }

    /// Advances every figure's pop cycle; called once per rendered
    /// frame. Figure geometry is already `unit`-scaled, so the node
    /// scale is the bare pop envelope — a second `unit` factor would
    /// shrink model-run figures by `unit²` (asset units are meters).
    /// The rise lift stays in `unit` units so it lands ~9 scene
    /// units above the sill on either pivot convention.
    func update(at t: TimeInterval) {
        for figure in figures {
            let cycle = (t / period + figure.phase)
                .truncatingRemainder(dividingBy: 1)
            let pop = CGFloat(Self.popScale(cycle))
            figure.node.scale = SCNVector3(pop, pop, pop)
            figure.node.position.y = figure.anchorY
                + pop * figure.unit * 9
        }
    }

    /// Pop envelope over one cycle: hidden, quick rise, hold, sink.
    /// Returns 0 while hidden so degenerate geometry never rasterizes.
    private static func popScale(_ cycle: Double) -> Double {
        let c = cycle.truncatingRemainder(dividingBy: 1)
        switch c {
        case ..<0.2, 0.9...: return 0
        case 0.2..<0.4: return smoothstep((c - 0.2) / 0.2)
        case 0.4..<0.75: return 1
        default: return 1 - smoothstep((c - 0.75) / 0.15)
        }
    }

    private static func smoothstep(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return v * v * (3 - 2 * v)
    }

    /// One car window: dark glass, a sill bar, and two figures rising
    /// inside it on staggered phases.
    private func addWindow(at x: CGFloat, y: CGFloat, frontZ: CGFloat,
                           unit: CGFloat, seed: Int) {
        let windowWidth = 14 * unit
        let windowHeight = 19 * unit
        let window = SCNNode()
        window.name = "car-window"
        window.position = SCNVector3(x, y, frontZ)

        let glass = SCNNode(geometry: SCNPlane(
            width: windowWidth, height: windowHeight))
        glass.geometry?.materials = [Self.material(
            red: 0.07, green: 0.09, blue: 0.15)]
        window.addChildNode(glass)

        let sill = SCNNode(geometry: SCNBox(
            width: windowWidth + 3 * unit, height: 3 * unit,
            length: unit, chamferRadius: 0))
        sill.geometry?.materials = [Self.material(
            red: 0.35, green: 0.33, blue: 0.3)]
        sill.position = SCNVector3(
            0, -windowHeight / 2 - 1.5 * unit, unit)
        window.addChildNode(sill)

        let anchorY = -windowHeight / 2 + unit
        for j in 0..<2 {
            let figure = makeFigure(seed: seed * 2 + j, unit: unit)
            figure.scale = SCNVector3(0, 0, 0)
            figure.position = SCNVector3(
                (j == 0 ? -3.5 : 3.5) * unit, anchorY, 1.5 * unit)
            window.addChildNode(figure)
            figures.append((
                node: figure,
                phase: (Double(seed * 2 + j) * 0.6180339887)
                    .truncatingRemainder(dividingBy: 1),
                anchorY: anchorY, unit: unit))
        }
        root.addChildNode(window)
    }

    /// A ~12 pt person: skin-tone head over a capsule torso. Two shirt
    /// colors alternate so a crowd reads as a crowd, not a row.
    private func makeFigure(seed: Int, unit: CGFloat) -> SCNNode {
        let figure = SCNNode()
        figure.name = "screamer"

        let head = SCNNode(geometry: SCNSphere(radius: 2.4 * unit))
        head.geometry?.materials = [Self.material(
            red: 0.98, green: 0.72, blue: 0.55)]
        head.position = SCNVector3(0, 7.6 * unit, 0)
        figure.addChildNode(head)

        let body = SCNNode(geometry: SCNCapsule(
            capRadius: 2.2 * unit, height: 5.5 * unit))
        body.geometry?.materials = [Self.material(
            red: seed % 2 == 0 ? 0.75 : 0.3,
            green: seed % 2 == 0 ? 0.2 : 0.35,
            blue: seed % 2 == 0 ? 0.25 : 0.7)]
        body.position = SCNVector3(0, 2.2 * unit, 0)
        figure.addChildNode(body)

        return figure
    }

    private static func material(red: CGFloat, green: CGFloat,
                                 blue: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(
            calibratedRed: red, green: green, blue: blue, alpha: 1)
        return material
    }
}
