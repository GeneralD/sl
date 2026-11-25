import AppKit
import SceneKit

/// `-a` visual half (issue #37): tiny crowd figures that pop up inside
/// the car windows while the loco rocks. Every pose is a pure function
/// of `t` — no clock, no randomness — so spec checks and `--freeze`
/// shots see the same frame. Scream audio is the audio engine's job
/// (`RunSpec.wantScreams`); this type never touches sound.
@MainActor
final class ScreamerField {
    /// Window strip geometry in train-local points (train center 0,0,
    /// camera-facing side at +z).
    private static let windowWidth: CGFloat = 16
    private static let windowHeight: CGFloat = 22
    private static let windowY: CGFloat = 16
    private static let windowSpacing: CGFloat = 34
    private static let windowMargin: CGFloat = 20

    /// Seconds for one full pop cycle per figure.
    private let period: TimeInterval = 1.15

    /// Attach point: the renderer adds this node to the train.
    let root = SCNNode()
    private var figures: [(node: SCNNode, phase: Double, anchorY: CGFloat)] = []

    /// `trainSize` is the rendered train's pixel size; windows and
    /// figures are placed relative to it so they track `--model` swaps.
    init(trainSize: CGSize) {
        root.name = "screamers"
        let count = max(
            1, Int((trainSize.width - Self.windowMargin * 2)
                / Self.windowSpacing))
        let span = CGFloat(count - 1) * Self.windowSpacing
        let frontZ = trainSize.height / 2 + 1.5
        for i in 0..<count {
            addWindow(
                at: -span / 2 + CGFloat(i) * Self.windowSpacing,
                frontZ: frontZ, seed: i)
        }
    }

    /// Advances every figure's pop cycle; called once per rendered frame.
    func update(at t: TimeInterval) {
        for figure in figures {
            let cycle = (t / period + figure.phase)
                .truncatingRemainder(dividingBy: 1)
            let scale = CGFloat(Self.popScale(cycle))
            figure.node.scale = SCNVector3(scale, scale, scale)
            figure.node.position.y = figure.anchorY + scale * 9
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
    private func addWindow(at x: CGFloat, frontZ: CGFloat, seed: Int) {
        let window = SCNNode()
        window.name = "car-window"
        window.position = SCNVector3(x, Self.windowY, frontZ)

        let glass = SCNNode(geometry: SCNPlane(
            width: Self.windowWidth, height: Self.windowHeight))
        glass.geometry?.materials = [Self.material(
            red: 0.07, green: 0.09, blue: 0.15)]
        window.addChildNode(glass)

        let sill = SCNNode(geometry: SCNBox(
            width: Self.windowWidth + 3, height: 3, length: 1,
            chamferRadius: 0))
        sill.geometry?.materials = [Self.material(
            red: 0.35, green: 0.33, blue: 0.3)]
        sill.position = SCNVector3(
            0, -Self.windowHeight / 2 - 1.5, 1)
        window.addChildNode(sill)

        let anchorY = -Self.windowHeight / 2 + 1
        for j in 0..<2 {
            let figure = makeFigure(seed: seed * 2 + j)
            figure.scale = SCNVector3(0, 0, 0)
            figure.position = SCNVector3(
                j == 0 ? -3.5 : 3.5, anchorY, 1.5)
            window.addChildNode(figure)
            figures.append((
                node: figure,
                phase: (Double(seed * 2 + j) * 0.6180339887)
                    .truncatingRemainder(dividingBy: 1),
                anchorY: anchorY))
        }
        root.addChildNode(window)
    }

    /// A ~12 pt person: skin-tone head over a capsule torso. Two shirt
    /// colors alternate so a crowd reads as a crowd, not a row.
    private func makeFigure(seed: Int) -> SCNNode {
        let figure = SCNNode()
        figure.name = "screamer"

        let head = SCNNode(geometry: SCNSphere(radius: 2.4))
        head.geometry?.materials = [Self.material(
            red: 0.98, green: 0.72, blue: 0.55)]
        head.position = SCNVector3(0, 7.6, 0)
        figure.addChildNode(head)

        let body = SCNNode(geometry: SCNCapsule(
            capRadius: 2.2, height: 5.5))
        body.geometry?.materials = [Self.material(
            red: seed % 2 == 0 ? 0.75 : 0.3,
            green: seed % 2 == 0 ? 0.2 : 0.35,
            blue: seed % 2 == 0 ? 0.25 : 0.7)]
        body.position = SCNVector3(0, 2.2, 0)
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
