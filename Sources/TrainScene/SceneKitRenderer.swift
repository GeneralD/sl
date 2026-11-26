import AppKit
import OverlayKit
import SceneKit
import SLCore

/// The committed renderer (spike B, docs/adr/scene.md): a transparent
/// `SCNView` hosting one ortho camera in a 3/4 overhead pose — scene
/// units are lane points, foreshortened by the tilt — lit by ambient +
/// directional lights. The bundled `model-loco` asset (or a `--model`
/// swap) is driven by `Trajectory`.
///
/// HDR/exposure adaptation stays OFF: clear pixels read as black to the
/// exposure solver and darken the whole strip.
@MainActor
public final class SceneKitRenderer: Renderer {
    private let trajectory: Trajectory
    private let model: ModelAsset.Loaded?
    private let locoScale: CGFloat
    /// Lane strip height in points — the ghost-steam clamps are
    /// fractions of the design lane, so they follow the real strip.
    private let laneHeight: CGFloat
    private weak var train: SCNNode?
    private var locoMaterials: [SCNMaterial] = []
    private weak var ambientNode: SCNNode?
    private weak var keyNode: SCNNode?
    private var disco: DiscoTimeline?
    /// Consist center offset from the loco pivot: cars all trail +x, so
    /// the coupled train's midpoint sits half the car chain past the
    /// loco's own center. `render` subtracts this so `pose.x` keeps
    /// meaning "center of the whole consist".
    private var consistShift: CGFloat = 0
    /// `-<n>` cars and their scale, resolved once in `init` so the
    /// trajectory width and the node tree agree.
    private var carCount: Int = 0
    private var carScale: CGFloat = 1
    /// The bundled tender/coaches coupled behind the locomotive;
    /// empty when no cars are requested or the assets are missing
    /// (`sl` preflights the consist so a real run exits 2 first).
    private var modelCars: [ModelConsist.Car] = []
    private var screamers: ScreamerField?
    /// `-a` panic: the loco rocks slightly while screamers pop.
    private var rocking = false
    private weak var scene: SCNScene?
    /// Ghost steam: the emitter dropped at the exit frame, the scene
    /// it hangs off, and when the consist cleared the lane.
    private var ghost: SCNNode?
    private var ghostSystem: SCNParticleSystem?
    private var exitedAt: TimeInterval?
    /// The train node's resting scale — `--model` wrappers carry a
    /// normalization scale and `-l` multiplies it, so `-d`'s pulse
    /// scales on top of this instead of replacing it.
    private var baseScale = SCNVector3(1, 1, 1)
    /// Rolling gear on a rigged model (drivers, wheelsets, rods) —
    /// nil when the loaded asset names no wheelwork nodes.
    private var wheelwork: ModelWheelwork?
    /// The pose x from the previous frame — wheel roll is the
    /// accumulated translation, so `-w`, `--scale` and `-l` compose
    /// for free and pausing the pose stops the wheels too.
    private var lastPoseX: Float?

    /// Two strobe colors the scene lights alternate between under `-d`.
    private static let discoPalette = [
        NSColor(calibratedRed: 1.0, green: 0.1, blue: 0.8, alpha: 1),   // magenta
        NSColor(calibratedRed: 0.1, green: 0.9, blue: 1.0, alpha: 1),   // cyan
    ]

    /// `-l` miniature factor; multiplies the lane scale like `--scale`.
    private static let littleScale: CGFloat = 0.6

    /// Seconds the window holds after the consist clears the lane so
    /// the ghost-steam trail can dissipate before the finish fade.
    public static let ghostSteamDuration: TimeInterval = 1.0
    /// How long the dropped emitter keeps firing after exit — beyond
    /// this the puffs only decay.
    private static let ghostEmitWindow: TimeInterval = 0.3

    public let duration: TimeInterval

    /// `model` is a locomotive asset already normalized by
    /// `ModelAsset.loadTrain`; when absent the bundled default (or a
    /// `spec.model` path) is re-loaded defensively — `sl` preflights
    /// the load so a bad path exits 2 before the window opens.
    ///
    /// `laneHeight` is the strip's height in points: the lane grew to
    /// ~60% of screen height, so the whole scene scales by
    /// `laneHeight / referenceLaneHeight` on top of `--scale`/`-l`.
    public init(spec: RunSpec, stripWidth: CGFloat,
                model: ModelAsset.Loaded? = nil,
                dock: [DockZone] = [],
                laneHeight: CGFloat = OverlayGeometry.referenceLaneHeight) {
        precondition(laneHeight > 0)
        self.laneHeight = laneHeight
        // The lane-height ratio scales every lane-fraction of the
        // design scene; `--scale` and `-l` multiply on top. A model
        // is normalized to the locomotive's design height, so the
        // same `locoScale` lands it at the design size.
        let laneScale = laneHeight / OverlayGeometry.referenceLaneHeight
        let userScale = spec.scale.isFinite && spec.scale > 0
            ? spec.scale : 1
        let loaded = model ?? Self.loadModel(spec: spec)
        locoScale = laneScale
            * (spec.little ? Self.littleScale : 1)
            * CGFloat(userScale)
        // A model is normalized to the locomotive's design height, so
        // its node scale and reported size take the same factor.
        let trainSize: CGSize
        if let loaded {
            trainSize = CGSize(
                width: loaded.size.width * locoScale,
                height: loaded.size.height * locoScale)
        } else {
            // Unreachable in a real run (`sl` exits 2 first); keeps
            // the trajectory's positive-size precondition satisfied.
            trainSize = CGSize(
                width: ModelAsset.locomotiveDesignHeight * locoScale,
                height: ModelAsset.locomotiveDesignHeight * locoScale)
        }
        carCount = spec.cars
        carScale = locoScale
        // Couple the bundled tender/coaches (real proportions, lengths
        // feed the trajectory); a missing consist renders no cars —
        // `sl` preflights it so a real run exits 2 before this point.
        let carsLength: CGFloat
        if loaded != nil, carCount > 0,
           let consist = ModelConsist.load(carCount: carCount) {
            modelCars = consist
            carsLength = ModelConsist.chainLength(cars: consist) * carScale
        } else {
            carsLength = 0
        }
        consistShift = carsLength / 2
        // `-w` shortens the crossing: the consist width includes the
        // car chain so the last car clears the left edge before
        // `finished` flips.
        let trajectory = Trajectory(
            laneWidth: Double(stripWidth),
            trainWidth: Double(trainSize.width + carsLength),
            trainHeight: Double(trainSize.height),
            duration: 8 / spec.speedFactor,
            fly: spec.fly,
            dock: dock
        )
        self.trajectory = trajectory
        self.model = loaded
        duration = trajectory.duration
    }

    /// Resolves the locomotive asset: `spec.model == nil` and the
    /// `loco` alias both land on the bundled `loco.usdz`; anything
    /// else is a user-supplied path. Returns nil only when the asset
    /// cannot be loaded — `sl` preflights and exits 2 first.
    @MainActor
    private static func loadModel(spec: RunSpec) -> ModelAsset.Loaded? {
        let path = spec.model ?? "loco"
        let resolved = path == "loco"
            ? modelAssetURL(named: "loco.usdz")?.path ?? path
            : path
        return try? ModelAsset.loadTrain(
            at: resolved,
            targetHeight: ModelAsset.locomotiveDesignHeight)
    }

    public func makeView(in frame: NSRect, spec: RunSpec) -> NSView {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        self.scene = scene

        addAmbientLight(to: scene)
        addKeyLight(to: scene)
        addCamera(to: scene, frame: frame)

        let train: SCNNode
        if let model {
            train = model.node
            // The model carries no `chimney`/`headlight` names —
            // synthesize bbox-derived anchors BEFORE the `locoScale`
            // multiply (the helper reads the wrapper's normalization
            // transform), then attach the shared effects with scale 1:
            // anchor-local units are design units, so ancestors apply
            // `locoScale` exactly like the procedural loco's baked
            // scale did.
            anchorModelLocomotiveEffects(on: train, size: model.size)
            train.scale = SCNVector3(
                train.scale.x * locoScale, train.scale.y * locoScale,
                train.scale.z * locoScale)
            attachLocomotiveEffects(to: train)
        } else {
            // Only reachable when the locomotive asset itself cannot
            // be loaded — `sl` exits 2 before this in a real run.
            train = SCNNode()
            train.name = "model-loco"
        }
        // `-<n>` coupling: the chain rides inside the train node so it
        // inherits pose, heading and disco. The chain lives in the
        // train's local space — the `model-loco` wrapper pre-scales
        // that space, so the chain counter-scales to keep lane size.
        // `modelCars` is only populated when `model` loaded, so the
        // chain's rear anchor always comes from the normalized size.
        if carCount > 0, !modelCars.isEmpty, let model {
            let nodeScale = CGFloat(train.scale.x)
            // Design -> wrapper-local: the wrapper's normalization
            // scale alone (nodeScale/locoScale), not nodeScale —
            // dividing by nodeScale shrank the anchor by locoScale,
            // tucking the chain toward the loco's center and lifting
            // the cars off the rail.
            let norm = nodeScale / locoScale
            let chain = ModelConsist.chain(cars: modelCars)
            chain.scale = SCNVector3(
                carScale / nodeScale, carScale / nodeScale,
                carScale / nodeScale)
            chain.position = SCNVector3(
                Float(model.size.width / 2 / norm),
                Float(-model.size.height / 2 / norm), 0)
            train.addChildNode(chain)
        }
        scene.rootNode.addChildNode(train)
        self.train = train
        baseScale = train.scale
        locoMaterials = Self.materials(of: train)
        // Wheelwork reads the wrapper's final scale, so it must init
        // after `locoScale` landed and the node sits in the scene.
        if let model, model.node === train {
            let rig = ModelWheelwork(root: train)
            wheelwork = rig.engaged ? rig : nil
        }

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
            // boundingBox covers the whole subtree in train-local
            // space, so windows land correctly for the procedural
            // loco's track-contact pivot and centered --model pivots.
            let bounds = train.boundingBox
            let field = ScreamerField(bounds: bounds.min, hi: bounds.max)
            train.addChildNode(field.root)
            screamers = field
        }
        return view
    }

    /// Right-to-left like the original: `Trajectory` owns the math.
    /// The `model-loco` pivot is centered, so the pose's y lands
    /// as-is.
    public func render(at t: TimeInterval) {
        guard let train else { return }
        let pose = trajectory.pose(at: t)
        train.position = SCNVector3(
            CGFloat(pose.x) - consistShift,
            CGFloat(pose.y), 0)
        train.eulerAngles.z = CGFloat(pose.heading)
        if let lastPoseX, let wheelwork {
            // Travel is -x, so forward distance is last - current.
            wheelwork.advance(by: lastPoseX - Float(pose.x))
        }
        lastPoseX = Float(pose.x)
        if rocking {
            screamers?.update(at: t)
            // Slight panic roll toward the camera — small enough to
            // read as distress, not a crash.
            train.eulerAngles.x = CGFloat(sin(t * 2.6) * 0.045)
        }
        if let disco {
            applyDisco(t: t, timeline: disco)
        }
        guard pose.finished else { return }
        dropGhostSteam(at: t)
        stopGhostEmission(at: t)
    }

    /// First finished frame: drop a ghost-steam emitter where the
    /// train was — the chimney smoke's world position when the loco
    /// carries one, the train origin otherwise — and stamp the exit
    /// time the post-exit hold counts down from.
    private func dropGhostSteam(at t: TimeInterval) {
        if exitedAt == nil { exitedAt = t }
        guard ghost == nil, let scene else { return }
        var origin = train?
            .childNode(withName: "smoke", recursively: true)?
            .worldPosition ?? train?.worldPosition ?? SCNVector3Zero
        // `finished` flips only after the whole consist is past the
        // left edge — the raw origin is already offscreen and its
        // puffs would die before drifting into view. Slide the
        // emitter onto the lane's left end, where the train was last
        // seen, and lift it into the lane band so the fog hangs over
        // the lane. (The emitter's 240-wide shell spans x±120.)
        // The y clamps are fractions of the design lane — the strip
        // is taller now, so they scale with `laneHeight`.
        origin.x = min(max(origin.x, 160), 200)
        let design = OverlayGeometry.referenceLaneHeight
        origin.y = min(max(origin.y,
            laneHeight * 40 / design), laneHeight * 160 / design)
        let node = ghostSteamEmitter(scale: locoScale)
        node.position = origin
        scene.rootNode.addChildNode(node)
        ghost = node
        ghostSystem = node.particleSystems?.first
    }

    /// The emitter fires only through `ghostEmitWindow` after exit;
    /// past that the puffs decay on their own particleLifeSpan.
    private func stopGhostEmission(at t: TimeInterval) {
        guard let exitedAt, let ghostSystem,
              t - exitedAt > Self.ghostEmitWindow else { return }
        ghostSystem.birthRate = 0
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
        train?.scale = SCNVector3(
            baseScale.x * s, baseScale.y * s, baseScale.z * s)
    }

    @discardableResult
    public func step(to t: TimeInterval) -> Bool {
        render(at: t)
        return !trajectory.pose(at: t).finished
    }

    /// The ghost-steam hold: the run loop keeps the window up this
    /// long past exit so the trail dissipates before the fade.
    public var postExitHold: TimeInterval { Self.ghostSteamDuration }

    public func postExitRemaining(at t: TimeInterval) -> TimeInterval {
        guard let exitedAt else { return 0 }
        return max(0, Self.ghostSteamDuration - (t - exitedAt))
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

    /// 3/4 overhead ortho camera: elevated ~37° toward the viewer
    /// (+z, out of the lane plane) so boiler crowns, domes, the cab
    /// roof and the wheel/rod depth read on screen. The offset stays
    /// in the y-z plane — any x yaw would rotate the consist off the
    /// lane's horizontal and break the right-to-left read. `look(at:)`
    /// keeps the horizon level. `orthographicScale` stays height/2:
    /// ortho scale is isotropic, so zooming to compensate the ~0.8
    /// vertical foreshortening would crop the consist's width instead —
    /// the train lands a touch smaller than the old side-on framing.
    /// One world unit is no longer one screen point (docs/adr/scene.md).
    private func addCamera(to scene: SCNScene, frame: NSRect) {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(frame.height / 2)
        camera.zNear = -5000
        camera.zFar = 5000
        let node = SCNNode()
        node.camera = camera
        let target = SCNVector3(
            Float(frame.width / 2), Float(frame.height / 2), 0)
        // Offset = (0, 0.6, 0.8) × 1500 pt: straight up-and-toward.
        node.position = SCNVector3(
            target.x, target.y + 900, 1200)
        node.look(at: target)
        scene.rootNode.addChildNode(node)
    }

    /// Every material in the loco's subtree — procedural node tree or a
    /// user-supplied model graph — so `-d` hue-cycles the whole body.
    private static func materials(of node: SCNNode) -> [SCNMaterial] {
        let own = node.geometry?.materials.compactMap {
            $0 as? SCNMaterial
        } ?? []
        return own + node.childNodes.flatMap { materials(of: $0) }
    }
}
