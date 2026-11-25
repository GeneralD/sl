import AppKit
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
    private static let trainSize = CGSize(width: 220, height: 90)

    private let trajectory: Trajectory
    private weak var train: SCNNode?

    public let duration: TimeInterval

    public init(spec: RunSpec, stripWidth: CGFloat) {
        let trajectory = Trajectory(
            laneWidth: Double(stripWidth),
            trainWidth: Double(Self.trainSize.width),
            trainHeight: Double(Self.trainSize.height),
            duration: 8
        )
        self.trajectory = trajectory
        duration = trajectory.duration
    }

    public func makeView(in frame: NSRect, spec: RunSpec) -> NSView {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        addAmbientLight(to: scene)
        addKeyLight(to: scene)
        addCamera(to: scene, frame: frame)

        let train = SCNNode(geometry: Self.placeholderGeometry())
        train.name = "placeholder-loco"
        scene.rootNode.addChildNode(train)
        self.train = train

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
        return view
    }

    /// Right-to-left like the original: `Trajectory` owns the math.
    /// The slow yaw is placeholder-only — it proves the lighting rig
    /// until wheels and rods give the loco real motion.
    public func render(at t: TimeInterval) {
        guard let train else { return }
        let pose = trajectory.pose(at: t)
        train.position = SCNVector3(
            CGFloat(pose.x), CGFloat(pose.y), 0)
        train.eulerAngles.y = CGFloat(t * 0.9)
        train.eulerAngles.z = CGFloat(pose.heading)
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
            width: trainSize.width, height: trainSize.height,
            length: trainSize.height, chamferRadius: 10)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(
            calibratedRed: 0.62, green: 0.25, blue: 0.18, alpha: 1)
        box.materials = [material]
        return box
    }
}
