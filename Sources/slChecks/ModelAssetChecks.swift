import AppKit
import OverlayKit
import SceneKit
import SLCore
import SLTestKit
import TrainScene

/// Fresh temp directory holding one fixture file; caller removes it.
private func writeFixture(_ name: String, contents: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("sl-model-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: true)
    try contents.write(
        to: dir.appendingPathComponent(name),
        atomically: true, encoding: .utf8)
    return dir
}

/// A real .scn: an archived SCNScene — the format Xcode writes and
/// `SCNScene(url:)` reads. `empty` skips the geometry so the bounding
/// box degenerates.
@MainActor
private func writeSCNFixture(
    _ name: String, width: CGFloat = 10, height: CGFloat = 20,
    depth: CGFloat = 5, empty: Bool = false
) throws -> URL {
    let scene = SCNScene()
    if !empty {
        scene.rootNode.addChildNode(SCNNode(geometry: SCNBox(
            width: width, height: height, length: depth, chamferRadius: 0)))
    }
    let data = try NSKeyedArchiver.archivedData(
        withRootObject: scene, requiringSecureCoding: false)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("sl-model-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent(name))
    return dir
}

@MainActor
private func expectLoadError(
    _ path: String, _ expected: ModelAsset.LoadError
) throws {
    do {
        _ = try ModelAsset.loadTrain(
            at: path, targetHeight: ProceduralLocomotive.size.height)
        try expect(false, "loadTrain should throw \(expected)")
    } catch let error as ModelAsset.LoadError {
        try expectEqual(error, expected)
        try expect(error.description.count > 0)
    }
}

/// `RunSpec.parse` returns Result; fixture args always parse.
private func parsedSpec(_ args: [String]) -> RunSpec {
    switch RunSpec.parse(args) {
    case .success(let spec): return spec
    case .failure(let error): fatalError("fixture args must parse: \(error)")
    }
}

public let modelAssetChecks: [Check] = [
    Check("when the bundled model is requested it resolves to an existing usdz") {
        guard let url = modelAssetURL(named: "loco.usdz") else {
            throw CheckFailure(message: "model asset directory unresolved")
        }
        try expect(FileManager.default.fileExists(atPath: url.path))
        try expect(url.pathExtension == "usdz")
    },
    Check("when the model path does not exist loadTrain throws file not found") {
        try MainActor.assumeIsolated {
            try expectLoadError(
                "/nonexistent/sl-definitely-missing.usdz", .missingFile)
        }
    },
    Check("when the model extension is unsupported loadTrain rejects it as USDZ/SCN/DAE only") {
        let dir = try writeFixture("train.glb", contents: "not really a glb")
        defer { try? FileManager.default.removeItem(at: dir) }
        try MainActor.assumeIsolated {
            try expectLoadError(
                dir.appendingPathComponent("train.glb").path,
                .unsupportedFormat("glb"))
        }
    },
    Check("when the model file is not a scene loadTrain throws unreadable") {
        let dir = try writeFixture("broken.scn", contents: "this is not a scene")
        defer { try? FileManager.default.removeItem(at: dir) }
        try MainActor.assumeIsolated {
            try expectLoadError(
                dir.appendingPathComponent("broken.scn").path, .unreadable)
        }
    },
    Check("when the model scene has no geometry loadTrain throws unreadable") {
        try MainActor.assumeIsolated {
            let dir = try writeSCNFixture("empty.scn", empty: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            try expectLoadError(
                dir.appendingPathComponent("empty.scn").path, .unreadable)
        }
    },
    Check("when a .scn fixture loads loadTrain returns a named model node") {
        try MainActor.assumeIsolated {
            let dir = try writeSCNFixture("fixture.scn")
            defer { try? FileManager.default.removeItem(at: dir) }
            let loaded = try ModelAsset.loadTrain(
                at: dir.appendingPathComponent("fixture.scn").path,
                targetHeight: ProceduralLocomotive.size.height)
            try expectEqual(loaded.node.name, "model-loco")
            try expect(loaded.size.height == ProceduralLocomotive.size.height)
            try expect(loaded.size.width > 0)
        }
    },
    Check("when a model loads loadTrain normalizes height to the locomotive design height") {
        try MainActor.assumeIsolated {
            // Source box is 100 wide × 50 high; target 200 means ×4.
            let dir = try writeSCNFixture(
                "sized.scn", width: 100, height: 50, depth: 20)
            defer { try? FileManager.default.removeItem(at: dir) }
            let loaded = try ModelAsset.loadTrain(
                at: dir.appendingPathComponent("sized.scn").path,
                targetHeight: 200)
            try expectEqual(loaded.size.height, 200)
            try expectEqual(loaded.size.width, 400)
            try expect(loaded.node.childNodes.contains {
                $0.geometry != nil || !$0.childNodes.isEmpty
            })
        }
    },
    Check("when a model is supplied the SceneKit renderer swaps the procedural locomotive for the model node") {
        try MainActor.assumeIsolated {
            let dir = try writeSCNFixture("train.scn")
            defer { try? FileManager.default.removeItem(at: dir) }
            let path = dir.appendingPathComponent("train.scn").path
            let spec = parsedSpec(["sl", "--model", path])
            let loaded = try ModelAsset.loadTrain(
                at: path, targetHeight: ProceduralLocomotive.size.height)
            let renderer = SceneKitRenderer(
                spec: spec, stripWidth: 1000, model: loaded)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: spec) as? SCNView,
                  let scene = view.scene,
                  let loco = scene.rootNode.childNode(
                    withName: "model-loco", recursively: true) else {
                try expect(false, "renderer produced no model node")
                return
            }
            try expect(scene.rootNode.childNode(
                withName: "procedural-locomotive", recursively: true) == nil)
            renderer.render(at: 0)
            let earlyX = loco.position.x
            renderer.render(at: 1)
            renderer.render(at: 7)
            try expect(loco.position.x < earlyX)
        }
    },
    Check("when spec names a model but none is preloaded the renderer loads it defensively") {
        try MainActor.assumeIsolated {
            let dir = try writeSCNFixture("train.scn")
            defer { try? FileManager.default.removeItem(at: dir) }
            let path = dir.appendingPathComponent("train.scn").path
            let spec = parsedSpec(["sl", "--model", path])
            let renderer = SceneKitRenderer(spec: spec, stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: spec) as? SCNView,
                  let scene = view.scene else {
                try expect(false, "renderer produced no scene")
                return
            }
            try expect(scene.rootNode.childNode(
                withName: "model-loco", recursively: true) != nil)
        }
    },
]
