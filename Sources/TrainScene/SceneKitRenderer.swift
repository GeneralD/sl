import AppKit
import CoreImage
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
    /// Lane strip height in points.
    private let laneHeight: CGFloat
    private weak var train: SCNNode?
    private var locoMaterials: [SCNMaterial] = []
    private weak var ambientNode: SCNNode?
    private weak var keyNode: SCNNode?
    private var disco: DiscoTimeline?
    /// Shared filter context for `--color` texture resprays.
    private lazy var ciContext = CIContext()
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
        addCamera(to: scene, frame: frame, azimuth: spec.viewAngle)

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
        if let livery = spec.livery { applyLivery(livery, to: scene) }
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
            // Windows belong on the passenger coaches — the loco and
            // tender carry none (the earlier whole-consist band floated
            // a window over the loco nose and starved the last car).
            // Each model-coach node's bounds convert to train space;
            // coaches are axis-aligned under the chain so the two
            // corners suffice. No coaches means no windows.
            let chain = train.childNode(
                withName: "car-chain", recursively: true)
            let cars = (chain?.childNodes ?? []).compactMap { node
                -> (lo: SCNVector3, hi: SCNVector3)? in
                guard node.name?.hasPrefix("model-coach") == true
                else { return nil }
                let b = node.boundingBox
                let p0 = node.convertPosition(b.min, to: train)
                let p1 = node.convertPosition(b.max, to: train)
                return (
                    lo: SCNVector3(
                        min(p0.x, p1.x), min(p0.y, p1.y), min(p0.z, p1.z)),
                    hi: SCNVector3(
                        max(p0.x, p1.x), max(p0.y, p1.y), max(p0.z, p1.z)))
            }
            let field = ScreamerField(cars: cars)
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
    }

    /// Which repaint a material took: none (neutral, skipped), body
    /// paint, or the livery's accent — accents keep their specular
    /// pop (polished metal on matte paint), body and texture go dead.
    private enum Repaint { case none, body, accent }

    /// `--color` respray: repaint materials whose own color is
    /// saturated enough to read as paintwork — neutral parts (coal,
    /// metals, cab interior, glazing) keep their finish. Each Livery
    /// component overrides independently: named hues keep the part's
    /// own saturation and brightness so the livery's shading
    /// survives; `black`/`gray` pull saturation for a neutral finish.
    /// Textured materials get the same treatment through a hue-rotate
    /// of the atlas — grays have no hue, so coal and metal stay put
    /// while the paint moves. One-shot at scene build — `-d`'s
    /// per-frame strobe simply overrides the colors again while it
    /// runs.
    private func applyLivery(_ livery: RunSpec.Livery, to scene: SCNScene) {
        var cache: [ObjectIdentifier: CGImage] = [:]
        for material in locoMaterials {
            guard let contents = material.diffuse.contents
            else { continue }
            if let color = contents as? NSColor {
                if resprayColor(material, color, livery) == .body,
                   livery.matte {
                    mattify(material)
                }
            } else if let object = contents as? AnyObject {
                let key = ObjectIdentifier(object)
                if cache[key] == nil,
                   let input = ciImage(of: contents) {
                    cache[key] = resprayed(input, to: livery)
                }
                if let atlas = cache[key] {
                    material.diffuse.contents = atlas
                    if livery.matte { mattify(material) }
                }
            }
        }
        if livery.matte { stageMatteLighting(in: scene) }
    }

    /// Matte-black dimensionality: a near-black body loses its diffuse
    /// shading, so the form must read through light, not paint. A rim
    /// light behind and above the lane catches the boiler crown and
    /// far-flank edges while the camera side stays dead — and a soft
    /// studio-box environment lays a sky-to-ground sheen gradient
    /// along the flanks (IBL, not a visible backdrop).
    private func stageMatteLighting(in scene: SCNScene) {
        let node = SCNNode()
        node.name = "rim-light"
        node.light = SCNLight()
        node.light?.type = .directional
        node.light?.intensity = 750
        node.light?.color = NSColor(
            calibratedRed: 0.95, green: 0.97, blue: 1, alpha: 1)
        // Behind (-z) and high: directional light rakes the crown and
        // the edges facing away from the trackside camera.
        node.position = SCNVector3(500, 420, -420)
        node.look(at: SCNVector3(500, 90, 0))
        scene.rootNode.addChildNode(node)
        scene.lightingEnvironment.contents = studioEnvironment()
        scene.lightingEnvironment.intensity = 0.65
    }

    /// A 3-stop vertical gradient standing in for a softbox: bright
    /// sky band over a dark ground, reflected faintly in the mattified
    /// paint so the boiler's curvature reads as a sheen sweep.
    private func studioEnvironment() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) {
            rect in
            NSGradient(colors: [
                NSColor(calibratedWhite: 0.9, alpha: 1),
                NSColor(calibratedWhite: 0.35, alpha: 1),
                NSColor(calibratedWhite: 0.08, alpha: 1),
            ])?.draw(in: rect, angle: -90)
            return true
        }
    }

    /// Solid-color paintwork: absolute overrides per component, gated
    /// to colors saturated enough to read as paint. The livery's
    /// accent band (the orange-family fittings) repaints to the
    /// accent colour instead of the body — gold domes on matte black.
    private func resprayColor(
        _ material: SCNMaterial, _ color: NSColor,
        _ livery: RunSpec.Livery
    ) -> Repaint {
        guard let hsb = color.usingColorSpace(.deviceRGB)
        else { return .none }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        var a: CGFloat = 0
        hsb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s >= 0.2, b >= 0.15 else { return .none }
        if let accent = livery.accent, accent.hueRange.contains(h) {
            material.diffuse.contents = NSColor(
                hue: CGFloat(accent.hue),
                saturation: CGFloat(accent.saturation),
                brightness: CGFloat(accent.brightness),
                alpha: a)
            return .accent
        }
        // Same floor as the texture path: a named hue also lifts
        // muted paint so the respray reads.
        let sat = livery.saturation.map { CGFloat($0) }
            ?? (livery.hue != nil ? max(s, 0.68) : s)
        material.diffuse.contents = NSColor(
            hue: livery.hue.map { CGFloat($0) } ?? h,
            saturation: sat,
            brightness: livery.brightness.map { CGFloat($0) } ?? b,
            alpha: a)
        return .body
    }

    /// Stove-black finish: specular drops to a broad whisper — dead
    /// paint, not vinyl, but enough left for the rim light and the
    /// environment sheen to trace the boiler's curvature. A touch of
    /// metalness lets the studio environment read on the flanks —
    /// matte paint still reflects the sky, just spread wide.
    private func mattify(_ material: SCNMaterial) {
        material.specular.contents = NSColor(white: 0.10, alpha: 1)
        material.shininess = 0.1
        material.metalness.contents = 0.35
    }

    /// Diffuse contents → CIImage. USDZ keeps its texture atlas inside
    /// the archive: the contents URL carries `?offset=&size=` byte
    /// ranges, which `CIImage(contentsOf:)` cannot open — slice the
    /// mapped file instead. Plain file URLs, CGImages and NSImages
    /// cover the other model formats.
    private func ciImage(of contents: Any) -> CIImage? {
        switch contents {
        case let url as URL:
            guard let range = usdzByteRange(of: url)
            else { return CIImage(contentsOf: url) }
            guard let data = try? Data(
                contentsOf: URL(fileURLWithPath: url.path),
                options: .alwaysMapped),
                range.offset >= 0, range.size > 0,
                range.offset + range.size <= data.count
            else { return nil }
            return CIImage(data: data.subdata(
                in: range.offset..<(range.offset + range.size)))
        case let image as CGImage:
            return CIImage(cgImage: image)
        case let image as NSImage:
            return image.cgImage(forProposedRect: nil, context: nil,
                                 hints: nil).map(CIImage.init(cgImage:))
        default:
            return nil
        }
    }

    /// Parses the `?offset=&size=` suffix USDZ gives embedded
    /// textures. Returns nil for ordinary file URLs.
    private func usdzByteRange(of url: URL) -> (offset: Int, size: Int)? {
        guard let items = URLComponents(
            url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let offset = items.first(where: { $0.name == "offset" })?
                .value.flatMap(Int.init),
            let size = items.first(where: { $0.name == "size" })?
                .value.flatMap(Int.init)
        else { return nil }
        return (offset, size)
    }

    /// Monotone-wash a texture atlas toward the livery:
    /// `CIColorMonochrome` folds the atlas's luminance shading into
    /// shades of the target colour — brightness detail (weathering,
    /// lining, wear) survives while every pixel takes the paint hue.
    /// Coal and metal join the same wash, which reads as overspray.
    private func resprayed(
        _ input: CIImage, to livery: RunSpec.Livery
    ) -> CGImage? {
        let paint = NSColor(
            hue: CGFloat(livery.hue ?? 0),
            saturation: CGFloat(livery.saturation ?? 0.72),
            brightness: CGFloat(livery.brightness ?? 0.62), alpha: 1)
        guard let out = CIFilter(name: "CIColorMonochrome",
                                 parameters: [
                                     kCIInputImageKey: input,
                                     kCIInputColorKey:
                                         CIColor(cgColor: paint.cgColor),
                                     kCIInputIntensityKey: 1.0,
                                 ])?.outputImage
        else { return nil }
        return ciContext.createCGImage(out, from: input.extent)
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

    /// 3/4 overhead ortho camera: elevated ~37° toward the viewer
    /// (+z, out of the lane plane) so boiler crowns, domes, the cab
    /// roof and the wheel/rod depth read on screen. `azimuth` rotates
    /// the horizontal reach toward the loco's front (-x): the consist
    /// then runs diagonally on screen and the smokebox face shows —
    /// the sketch-requested 3/4 look. 0 keeps the classic flat
    /// side-on ortho lane (the original task-71 framing). `look(at:)`
    /// keeps the horizon level.
    ///
    /// Angled runs switch to a *perspective* camera — ortho has no
    /// foreshortening, so the diagonal read as a flat slide, not an
    /// approach (user-reported). The angled camera sits lower and
    /// closer than the flat one — a ~20° trackside position ~858pt
    /// out, not the overhead 1500pt crane — so the near end passes
    /// ~510pt from the lens and the consist looms as it arrives.
    /// The field of view matches the ortho scale at the target
    /// plane (fov = 2·atan(scale/dist)), so the mid-lane size is
    /// unchanged while the far right end shrinks into the distance
    /// and the near left end grows past the camera.
    /// `orthographicScale` still tracks the taller `--angle` window
    /// for the 1:1 math above; `viewHeight` grows the frame upward so
    /// the drift fits (docs/adr/scene.md).
    private func addCamera(to scene: SCNScene, frame: NSRect,
                           azimuth: Double) {
        let camera = SCNCamera()
        let ortho = azimuth == 0
        camera.usesOrthographicProjection = ortho
        // Flat lane: the classic overhead ortho reach. Angled: a low
        // trackside camera pulled close to the rail — the near end
        // passes ~500pt out and looms hard over the lens.
        let reach: CGFloat = ortho ? 1200 : 840
        let height: CGFloat = ortho ? 900 : 170
        let dist = Double((reach * reach + height * height)
            .squareRoot())
        if ortho {
            camera.orthographicScale = Double(frame.height / 2)
            camera.zNear = -5000
            camera.zFar = 5000
        } else {
            camera.fieldOfView = 2 * atan2(
                Double(frame.height / 2), dist) * 180 / .pi
            camera.zNear = 1
            camera.zFar = 10000
        }
        let node = SCNNode()
        node.name = "camera"
        node.camera = camera
        let target = SCNVector3(
            Float(frame.width / 2), Float(laneHeight / 2), 0)
        // Azimuth swings the horizontal reach toward -x (front) so
        // the diagonal reads.
        let az = azimuth * .pi / 180
        let dx = reach * sin(az)
        let dz = reach * cos(az)
        node.position = SCNVector3(target.x - dx, target.y + height, dz)
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
