import Foundation
import SceneKit

/// User-supplied locomotive swap (`--model`): loads .usdz/.scn/.dae via
/// `SCNScene(url:)` — never a bare `MDLAsset`, which renders untextured
/// (docs/adr/scene.md) — and normalizes the bounding box to the
/// locomotive's design height, centered on the node origin like the
/// procedural loco; the renderer's `locoScale` then lands it at the
/// same on-screen size. glTF/GLB is NOT loadable; the supported set is
/// documented in `sl.1`, the README and the usage text.
public enum ModelAsset {
    /// A loaded, normalized train ready to drop into the scene graph.
    public struct Loaded {
        /// Node named `model-loco`; add it where the procedural loco goes.
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
        guard let scene = try? SCNScene(url: url, options: nil) else {
            throw LoadError.unreadable
        }
        return try normalized(scene, targetHeight: targetHeight)
    }

    /// Wraps the scene's content in a `model-loco` node scaled so the
    /// bounding-box height equals `targetHeight` (the locomotive's
    /// design height), with the box center on the node origin — the
    /// same anchor the placeholder geometry uses.
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
        let wrapper = SCNNode()
        wrapper.name = "model-loco"
        scene.rootNode.childNodes.forEach { wrapper.addChildNode($0) }
        wrapper.scale = SCNVector3(scale, scale, scale)
        wrapper.position = SCNVector3(
            -scale * (minX + maxX) / 2,
            -scale * (minY + maxY) / 2,
            -scale * (minZ + maxZ) / 2)
        return Loaded(
            node: wrapper,
            size: CGSize(width: boxWidth * scale, height: boxHeight * scale))
    }
}
