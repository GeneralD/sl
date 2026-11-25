import AppKit
import SceneKit
import SLCore

/// Spike B renderer: proves `SCNView` composites a transparent background
/// into the overlay window. Orthographic camera, scene units == screen
/// points; one spinning box slides right-to-left through the lane rect.
/// HDR/exposure adaptation stays OFF — clear pixels read as black to the
/// exposure solver and darken the whole strip (see docs/adr/scene.md).
@MainActor
public final class SceneKitRenderer: Renderer {
    private static let boxSize: CGFloat = 90

    private let stripWidth: CGFloat
    private var laneHeight: CGFloat = 0
    private var box: SCNNode?
    private var cameraNode: SCNNode?

    public let duration: TimeInterval = 8

    public init(spec: RunSpec, stripWidth: CGFloat) {
        self.stripWidth = stripWidth
    }

    public func makeView(in frame: NSRect, spec: RunSpec) -> NSView {
        laneHeight = frame.height

        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 700
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 900
        key.position = SCNVector3(-frame.width / 3, frame.height, 400)
        scene.rootNode.addChildNode(key)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(frame.height / 2)
        camera.zNear = -5000
        camera.zFar = 5000
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.position = SCNVector3(
            Double(frame.width / 2), Double(frame.height / 2), 1500)
        scene.rootNode.addChildNode(camNode)
        cameraNode = camNode

        let geometry = SCNBox(
            width: Self.boxSize, height: Self.boxSize,
            length: Self.boxSize, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.systemOrange
        material.lightingModel = .physicallyBased
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(0, Double(frame.height / 2), 0)
        scene.rootNode.addChildNode(node)
        box = node

        let view = SCNView(frame: frame, options: nil)
        view.scene = scene
        view.backgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.allowsCameraControl = false
        // wantsHDR/wantsExposureAdaptation stay at their defaults (off):
        // they live on SCNRenderer, not SCNView, and enabling them makes
        // the exposure solver read clear pixels as black.
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        return view
    }

    /// Right-to-left like the original: x runs from +width to -boxSize.
    public func render(at t: TimeInterval) {
        guard let box else { return }
        let p = min(max(t / duration, 0), 1)
        let x = stripWidth - (stripWidth + Self.boxSize) * p
        box.position.x = Double(x)
        box.eulerAngles.y = CGFloat(t * 2)
    }

    @discardableResult
    public func step(to t: TimeInterval) -> Bool {
        render(at: t)
        return t < duration
    }
}
