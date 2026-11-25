import AppKit
import OverlayKit
import SceneKit
import SLCore

/// The committed renderer (spike B, docs/adr/scene.md): a transparent
/// `SCNView` hosting one ortho camera in pixel space — scene units ==
/// screen points — lit by ambient + directional lights. The
/// `ProceduralLocomotive` node tree (or a `--model` asset) is driven by
/// `Trajectory`.
///
/// HDR/exposure adaptation stays OFF: clear pixels read as black to the
/// exposure solver and darken the whole strip.
@MainActor
public final class SceneKitRenderer: Renderer {
    private let trajectory: Trajectory
    private let model: ModelAsset.Loaded?
    private let livery: Livery
    private let locoScale: CGFloat
    private weak var train: SCNNode?
    private var locoMaterials: [SCNMaterial] = []
    private var wheelwork: WheelworkAnimator?
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
    private var screamers: ScreamerField?
    /// `-a` panic: the loco rocks slightly while screamers pop.
    private var rocking = false
    /// The train node's resting scale — `--model` wrappers carry a
    /// normalization scale and `-l` multiplies it, so `-d`'s pulse
    /// scales on top of this instead of replacing it.
    private var baseScale = SCNVector3(1, 1, 1)

    /// Two strobe colors the scene lights alternate between under `-d`.
    private static let discoPalette = [
        NSColor(calibratedRed: 1.0, green: 0.1, blue: 0.8, alpha: 1),   // magenta
        NSColor(calibratedRed: 0.1, green: 0.9, blue: 1.0, alpha: 1),   // cyan
    ]

    /// `-l` miniature factor (~0.6 of lane height); 1 is full size.
    private static let littleScale: CGFloat = 0.6

    public let duration: TimeInterval

    /// `model` is a `--model` asset already normalized by
    /// `ModelAsset.loadTrain`; when absent the procedural locomotive
    /// stands in. A `spec.model` with no `model` argument re-loads
    /// defensively — `sl` preflights the load so a bad path exits 2
    /// before the window opens.
    public init(spec: RunSpec, stripWidth: CGFloat,
                model: ModelAsset.Loaded? = nil,
                dock: [DockZone] = []) {
        let loaded = model ?? spec.model.flatMap {
            try? ModelAsset.loadTrain(
                at: $0, targetHeight: OverlayGeometry.laneHeight)
        }
        livery = Self.livery(for: spec)
        locoScale = spec.little ? Self.littleScale : 1
        // `-G` swaps the whole node builder, not just the paint: the
        // TGV bullet is longer and lower than the D51 silhouette, so
        // the trajectory measures whichever one will actually render.
        let proceduralSize = spec.tgv
            ? ProceduralTGV.size : ProceduralLocomotive.size
        let locoSize = CGSize(
            width: proceduralSize.width * locoScale,
            height: proceduralSize.height * locoScale)
        // `-l` shrinks the whole consist: a `--model` asset is
        // normalized to lane height, so its node scale and reported
        // size take the miniature factor too.
        let trainSize: CGSize
        if let loaded {
            trainSize = CGSize(
                width: loaded.size.width * locoScale,
                height: loaded.size.height * locoScale)
        } else {
            trainSize = locoSize
        }
        carCount = spec.cars
        carScale = locoScale
        let carsLength = Car.chainLength(n: carCount, scale: carScale)
        consistShift = carsLength / 2
        // `-w` shortens the crossing: trajectory speed is the wheelwork's
        // clock, so the running gear spins faster with it. The consist
        // width includes the car chain so the last car clears the left
        // edge before `finished` flips.
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

    /// `-c` selects the red-edged C51 livery; `-G` swaps in the TGV
    /// node builder in `makeView`, so it needs no livery slot.
    private static func livery(for spec: RunSpec) -> Livery {
        spec.c51 ? .c51 : .d51
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
            // `-l` multiplies the wrapper's normalization scale; the
            // car chain counter-scales off `train.scale` below.
            train.scale = SCNVector3(
                train.scale.x * locoScale, train.scale.y * locoScale,
                train.scale.z * locoScale)
        } else if spec.tgv {
            train = ProceduralTGV(scale: locoScale).node
        } else {
            train = ProceduralLocomotive(
                livery: livery, scale: locoScale).node
            attachLocomotiveEffects(to: train, scale: locoScale)
        }
        // `-<n>` coupling: the chain rides inside the train node so it
        // inherits pose, heading, wheelwork and disco. The chain lives
        // in the train's local space — a `--model` wrapper pre-scales
        // that space, so the chain counter-scales to keep lane size.
        if carCount > 0 {
            let nodeScale = CGFloat(train.scale.x)
            let rearX: CGFloat
            let bottomY: CGFloat
            if let model {
                rearX = model.size.width / 2
                bottomY = -model.size.height / 2
            } else {
                rearX = CGFloat(train.boundingBox.max.x)
                bottomY = 0
            }
            let chain = Car.cars(n: carCount)
            chain.scale = SCNVector3(
                carScale / nodeScale, carScale / nodeScale,
                carScale / nodeScale)
            chain.position = SCNVector3(
                Float(rearX / nodeScale), Float(bottomY / nodeScale), 0)
            train.addChildNode(chain)
        }
        scene.rootNode.addChildNode(train)
        self.train = train
        baseScale = train.scale
        locoMaterials = Self.materials(of: train)
        // Running gear rides only the procedural hooks — a `--model`
        // scene has no guaranteed `wheel-*`/`rod-*` names to drive.
        wheelwork = model == nil ? WheelworkAnimator(train: train) : nil

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
    /// The procedural loco's pivot is track contact, so its y sits half
    /// a train-height below the pose's box center; a `--model` asset is
    /// normalized to a centered pivot and takes the pose y as-is.
    public func render(at t: TimeInterval) {
        guard let train else { return }
        let pose = trajectory.pose(at: t)
        let pivotDrop = model == nil ? CGFloat(trajectory.trainHeight) / 2 : 0
        train.position = SCNVector3(
            CGFloat(pose.x) - consistShift,
            CGFloat(pose.y) - pivotDrop, 0)
        train.eulerAngles.z = CGFloat(pose.heading)
        if rocking {
            screamers?.update(at: t)
            // Slight panic roll toward the camera — small enough to
            // read as distress, not a crash.
            train.eulerAngles.x = CGFloat(sin(t * 2.6) * 0.045)
        }
        // Distance traveled since enter: the trajectory is linear, so
        // `startX - pose.x` is `speed * t` — the wheelwork's clock.
        let startX = trajectory.laneWidth + trajectory.margin
            + trajectory.trainWidth / 2
        wheelwork?.update(distance: CGFloat(startX - pose.x))
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
        train?.scale = SCNVector3(
            baseScale.x * s, baseScale.y * s, baseScale.z * s)
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

    /// Every material in the loco's subtree — procedural node tree or a
    /// user-supplied model graph — so `-d` hue-cycles the whole body.
    private static func materials(of node: SCNNode) -> [SCNMaterial] {
        let own = node.geometry?.materials.compactMap {
            $0 as? SCNMaterial
        } ?? []
        return own + node.childNodes.flatMap { materials(of: $0) }
    }
}
