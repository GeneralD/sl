import Foundation
import SceneKit

/// Locomotive assets: the bundled `share/sl/models/loco.usdz` is the
/// default train and `--model <file>` swaps in a custom one. Loads
/// .usdz/.scn/.dae via `SCNScene(url:)` — never a bare `MDLAsset`,
/// which renders untextured (docs/adr/scene.md) — and normalizes the
/// bounding box to `locomotiveDesignHeight`, centered on the node
/// origin; the renderer's `locoScale` then lands it at the design
/// size. glTF/GLB is NOT loadable; the supported set is documented in
/// `sl.1`, the README and the usage text.
public enum ModelAsset {
    /// The design-space height every locomotive normalizes to — the
    /// retired procedural loco's height, kept as the consist's meter
    /// so bundled cars keep their real-world proportions.
    public static let locomotiveDesignHeight: CGFloat = 154

    /// A loaded, normalized train ready to drop into the scene graph.
    public struct Loaded {
        /// Node named `model-loco`; add it where the train goes.
        public let node: SCNNode
        /// Normalized bounding-box size in scene units (== points).
        public let size: CGSize
    }

    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missingFile
        case unsupportedFormat(String)
        case unreadable

        public var description: String {
            switch self {
            case .missingFile:
                return "file not found"
            case .unsupportedFormat(let ext):
                return "unsupported format '.\(ext)' — USDZ/SCN/DAE only"
            case .unreadable:
                return "scene could not be parsed"
            }
        }
    }

    /// Extensions `SCNScene(url:)` can read; glTF/GLB is NOT among them.
    public static let supportedExtensions: Set<String> = ["usdz", "scn", "dae"]

    /// Load + normalize or throw `LoadError`. Callers surface the error
    /// on stderr and exit 2 before the run starts.
    @MainActor
    public static func loadTrain(at path: String,
                                 targetHeight: CGFloat) throws -> Loaded {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.missingFile
        }
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            throw LoadError.unsupportedFormat(url.pathExtension)
        }
        return try normalized(try scene(at: url),
                              targetHeight: targetHeight)
    }

    /// Raw bounding-box size of the asset at `path`, in the file's
    /// own units — the proportion reference `ModelConsist` scales the
    /// bundled cars against. Same `LoadError`s as `loadTrain`.
    @MainActor
    public static func sourceSize(at path: String) throws -> CGSize {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.missingFile
        }
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            throw LoadError.unsupportedFormat(url.pathExtension)
        }
        let box = try scene(at: url).rootNode.boundingBox
        let width = CGFloat(box.max.x - box.min.x)
        let height = CGFloat(box.max.y - box.min.y)
        guard width.isFinite, height.isFinite,
              width > 0, height > 0 else {
            throw LoadError.unreadable
        }
        return CGSize(width: width, height: height)
    }

    /// Raw bounding-box height of the asset at `path` — see
    /// `sourceSize`.
    @MainActor
    public static func sourceHeight(at path: String) throws -> CGFloat {
        try sourceSize(at: path).height
    }

    @MainActor
    private static func scene(at url: URL) throws -> SCNScene {
        guard let scene = try? SCNScene(url: url, options: nil) else {
            throw LoadError.unreadable
        }
        return scene
    }

    /// Wraps the scene's content in a `model-loco` node scaled so the
    /// bounding-box height equals `targetHeight` (normally
    /// `locomotiveDesignHeight`), with the box center on the node
    /// origin. The centering offset lives on an inner `model-content`
    /// node: callers own the wrapper's position (the renderer writes
    /// the trajectory pose into it every frame), so the wrapper
    /// carries only scale.
    @MainActor
    private static func normalized(_ scene: SCNScene,
                                   targetHeight: CGFloat) throws -> Loaded {
        let box = scene.rootNode.boundingBox
        let minX = CGFloat(box.min.x), maxX = CGFloat(box.max.x)
        let minY = CGFloat(box.min.y), maxY = CGFloat(box.max.y)
        let minZ = CGFloat(box.min.z), maxZ = CGFloat(box.max.z)
        let boxHeight = maxY - minY
        let boxWidth = maxX - minX
        guard boxHeight.isFinite, boxWidth.isFinite,
              boxHeight > 0, boxWidth > 0 else {
            throw LoadError.unreadable
        }
        let scale = targetHeight / boxHeight
        let content = SCNNode()
        content.name = "model-content"
        scene.rootNode.childNodes.forEach { content.addChildNode($0) }
        content.position = SCNVector3(
            -(minX + maxX) / 2, -(minY + maxY) / 2, -(minZ + maxZ) / 2)
        // Bundled assets are authored facing +x (smokebox toward the
        // cars); sl's forward is -x, so the content yaws half a turn
        // about the vertical axis — the centering offset puts the box
        // center on this node, so the model spins in place. Custom
        // --model files follow the same authored-facing-+x contract.
        content.eulerAngles.y = .pi
        let wrapper = SCNNode()
        wrapper.name = "model-loco"
        wrapper.scale = SCNVector3(scale, scale, scale)
        wrapper.addChildNode(content)
        return Loaded(
            node: wrapper,
            size: CGSize(width: boxWidth * scale, height: boxHeight * scale))
    }
}
