import AppKit
import OverlayKit
import SceneKit
import SLCore

/// The committed renderer (spike B, docs/adr/scene.md): a transparent
/// `SCNView` hosting one ortho camera in pixel space — scene units ==
/// screen points — lit by ambient + directional lights. A placeholder
/// primitive stands in for the locomotive until the real scene graph
/// lands; it is driven by `Trajectory`, same math as the placeholder
/// view renderer.
///
/// HDR/exposure adaptation stays OFF: clear pixels read as black to the
/// exposure solver and darken the whole strip.
@MainActor
public final class SceneKitRenderer: Renderer {
    /// Placeholder silhouette until the locomotive scene graph lands.
    private static let placeholderSize = CGSize(width: 220, height: 90)

    private let trajectory: Trajectory
    private let model: ModelAsset.Loaded?
    private let trainSize: CGSize
    private weak var train: SCNNode?
    private var locoMaterials: [SCNMaterial] = []
    private weak var ambientNode: SCNNode?
    private weak var keyNode: SCNNode?
    private var disco: DiscoTimeline?
    private var screamers: ScreamerField?
    /// `-a` panic: the loco rocks slightly while screamers pop.
    private var rocking = false

    /// Two strobe colors the scene lights alternate between under `-d`.
    private static let discoPalette = [
        NSColor(calibratedRed: 1.0, green: 0.1, blue: 0.8, alpha: 1),   // magenta
        NSColor(calibratedRed: 0.1, green: 0.9, blue: 1.0, alpha: 1),   // cyan
    ]

    public let duration: TimeInterval

    /// `model` is a `--model` asset already normalized by
    /// `ModelAsset.loadTrain`; when absent the placeholder primitive
    /// (soon the procedural loco) stands in. A `spec.model` with no
    /// `model` argument re-loads defensively — `sl` preflights the load
    /// so a bad path exits 2 before the window opens.
    public init(spec: RunSpec, stripWidth: CGFloat,
                model: ModelAsset.Loaded? = nil) {
        let loaded = model ?? spec.model.flatMap {
            try? ModelAsset.loadTrain(
                at: $0, targetHeight: OverlayGeometry.laneHeight)
        }
        let trainSize = loaded?.size ?? Self.placeholderSize
        let trajectory = Trajectory(
            laneWidth: Double(stripWidth),
            trainWidth: Double(trainSize.width),
            trainHeight: Double(trainSize.height),
            duration: 8,
            fly: spec.fly
        )
        self.trajectory = trajectory
        self.model = loaded
        self.trainSize = trainSize
        duration = trajectory.duration
    }

    public func makeView(in frame: NSRect, spec: RunSpec) -> NSView {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        addAmbientLight(to: scene)
        addKeyLight(to: scene)
        addCamera(to: scene, frame: frame)

        let train: SCNNode
        if let model {
            train = model.node
        } else {
            train = SCNNode(geometry: Self.placeholderGeometry())
            train.name = "placeholder-loco"
        }
        scene.rootNode.addChildNode(train)
        self.train = train
        locoMaterials = Self.materials(of: train)

        let view = SCNView(frame: frame, options: nil)
        view.scene = scene
        view.backgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.allowsCameraControl = false
        // rendersContinuously stays off: SCNView redraws on scene-graph
        // changes and render(at:) mutates node transforms every frame.
        view.rendersContinuously = false
        disco = spec.disco ? DiscoTimeline() : nil
        rocking = spec.accident
        if spec.accident {
            let field = ScreamerField(trainSize: trainSize)
            train.addChildNode(field.root)
            screamers = field
        }
        return view
    }

    /// Right-to-left like the original: `Trajectory` owns the math.
    /// The slow yaw is placeholder-only — it proves the lighting rig
    /// until wheels and rods give the loco real motion; a user-supplied
    /// model keeps its authored orientation.
    public func render(at t: TimeInterval) {
        guard let train else { return }
        let pose = trajectory.pose(at: t)
        train.position = SCNVector3(
            CGFloat(pose.x), CGFloat(pose.y), 0)
        if model == nil {
            train.eulerAngles.y = CGFloat(t * 0.9)
        }
        train.eulerAngles.z = CGFloat(pose.heading)
        if rocking {
            screamers?.update(at: t)
            // Slight panic roll toward the camera — small enough to
            // read as distress, not a crash.
            train.eulerAngles.x = CGFloat(sin(t * 2.6) * 0.045)
        }
        if let disco {
            applyDisco(t: t, timeline: disco)
        }
    }

    /// `-d` strobe: hue-cycled body color, lights alternating between
    /// the two palette colors (offset half a beat so they read as
    /// alternating), and a small beat-synced scale pulse. Timing lives
    /// in `DiscoTimeline` — seizure-safe rates are enforced there.
    private func applyDisco(t: TimeInterval, timeline: DiscoTimeline) {
        let hue = timeline.hue(at: t)
        let body = NSColor(
            hue: CGFloat(hue), saturation: 0.85,
            brightness: 0.95, alpha: 1)
        locoMaterials.forEach { $0.diffuse.contents = body }
        let beat = timeline.lightIndex(at: t)
        keyNode?.light?.color = Self.discoPalette[beat]
        ambientNode?.light?.color = Self.discoPalette[1 - beat]
        let s = CGFloat(timeline.scale(at: t))
        train?.scale = SCNVector3(s, s, s)
    }

    @discardableResult
    public func step(to t: TimeInterval) -> Bool {
        render(at: t)
        return !trajectory.pose(at: t).finished
    }

    private func addAmbientLight(to scene: SCNScene) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = .ambient
        node.light?.intensity = 700
        scene.rootNode.addChildNode(node)
        ambientNode = node
    }

    /// Directional "sun": position is irrelevant — the light travels
    /// along the node's -z axis, tilted down onto the lane.
    private func addKeyLight(to scene: SCNScene) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = .directional
        node.light?.intensity = 1000
        node.eulerAngles = SCNVector3(-0.5, 0.4, 0)
        scene.rootNode.addChildNode(node)
        keyNode = node
    }

    /// Ortho camera in pixel space: `orthographicScale = height/2` with
    /// the camera centered on the lane makes one scene unit == one
    /// screen point (docs/adr/scene.md).
    private func addCamera(to scene: SCNScene, frame: NSRect) {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(frame.height / 2)
        camera.zNear = -5000
        camera.zFar = 5000
        let node = SCNNode()
        node.camera = camera
        node.position = SCNVector3(
            frame.width / 2, frame.height / 2, 1500)
        scene.rootNode.addChildNode(node)
    }

    private static func placeholderGeometry() -> SCNGeometry {
        let box = SCNBox(
            width: placeholderSize.width, height: placeholderSize.height,
            length: placeholderSize.height, chamferRadius: 10)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(
            calibratedRed: 0.62, green: 0.25, blue: 0.18, alpha: 1)
        box.materials = [material]
        return box
    }

    /// Every material in the loco's subtree — placeholder box or a
    /// user-supplied model graph — so `-d` hue-cycles the whole body.
    private static func materials(of node: SCNNode) -> [SCNMaterial] {
        let own = node.geometry?.materials.compactMap {
            $0 as? SCNMaterial
        } ?? []
        return own + node.childNodes.flatMap { materials(of: $0) }
    }
}
