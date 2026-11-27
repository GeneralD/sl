import AppKit
import OverlayKit
import SceneKit
import SLCore
import SLTestKit
import TrainScene

/// `RunSpec.parse` returns Result; a bare `["sl"]` always succeeds.
private func defaultSpec() -> RunSpec {
    switch RunSpec.parse(["sl"]) {
    case .success(let spec): return spec
    case .failure(let error): fatalError("default spec must parse: \(error)")
    }
}

private func withRendererEnv<T>(_ value: String?, _ body: () throws -> T) rethrows -> T {
    let had = getenv("SL_RENDERER")
    let saved = had.map { String(cString: $0) }
    if let value { setenv("SL_RENDERER", value, 1) } else { unsetenv("SL_RENDERER") }
    defer {
        if let saved { setenv("SL_RENDERER", saved, 1) } else { unsetenv("SL_RENDERER") }
    }
    return try body()
}

/// Builds the renderer's view at a fixed lane size and returns its scene.
@MainActor
private func sceneKitScene(
    _ renderer: SceneKitRenderer,
    width: CGFloat = 1000, height: CGFloat = 180
) -> SCNScene? {
    guard let view = renderer.makeView(
        in: NSRect(x: 0, y: 0, width: width, height: height),
        spec: defaultSpec()) as? SCNView else { return nil }
    return view.scene
}

public let sceneKitChecks: [Check] = [
    Check("when SL_RENDERER is unset the factory returns the SceneKit renderer") {
        try MainActor.assumeIsolated {
            let renderer = withRendererEnv(nil) {
                RendererFactory.make(spec: defaultSpec(), stripWidth: 1000)
            }
            try expect(renderer is SceneKitRenderer)
        }
    },
    Check("when SL_RENDERER is placeholder the factory returns the placeholder renderer") {
        try MainActor.assumeIsolated {
            let renderer = withRendererEnv("placeholder") {
                RendererFactory.make(spec: defaultSpec(), stripWidth: 1000)
            }
            try expect(renderer is PlaceholderRenderer)
        }
    },
    Check("when the placeholder renderer is driven it builds a view and steps the train") {
        try MainActor.assumeIsolated {
            let renderer = PlaceholderRenderer(
                spec: defaultSpec(), stripWidth: 1000)
            let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: defaultSpec())
            try expect(view.subviews.count == 1,
                       "placeholder view holds no train glyph")
            try expect(renderer.step(to: 0))
            renderer.render(at: 1)
            try expect(!renderer.step(to: renderer.duration + 1))
        }
    },
    Check("when asked for its view the SceneKit renderer returns a clear SCNView") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(spec: defaultSpec(), stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: defaultSpec()) as? SCNView else {
                try expect(false, "view is not an SCNView")
                return
            }
            try expect(view.layer?.isOpaque == false)
            try expect(view.backgroundColor == .clear)
        }
    },
    Check("when asked for its view the SceneKit renderer configures a 3/4 overhead ortho camera") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(spec: defaultSpec(), stripWidth: 1000)
            guard let scene = sceneKitScene(renderer) else {
                try expect(false, "renderer produced no scene")
                return
            }
            guard let camNode = scene.rootNode.childNodes.first(where: { $0.camera != nil }),
                  let camera = camNode.camera else {
                try expect(false, "scene has no camera node")
                return
            }
            try expect(camera.usesOrthographicProjection)
            try expect(camera.orthographicScale == 90)
            // Elevated toward the viewer (+y, +z) with the default
            // 25° azimuth swinging toward the loco's front (-x):
            // x = 500 - 1200·sin(25°), z = 1200·cos(25°); pitched down,
            // yawed, level horizon (no roll).
            try expect(camNode.position.x < 500,
                       "camera did not swing toward -x: \(camNode.position)")
            try expect(camNode.position.y == 990)
            try expect(abs(camNode.position.z - 1200 * cos(25 * .pi / 180)) < 1,
                       "unexpected z reach: \(camNode.position.z)")
            try expect(camNode.eulerAngles.x < -0.3,
                       "camera not pitched down: \(camNode.eulerAngles)")
            try expect(abs(abs(camNode.eulerAngles.y) - 25 * .pi / 180) < 0.05,
                       "camera yaw off the azimuth: \(camNode.eulerAngles)")
            try expect(abs(camNode.eulerAngles.z) < 0.001,
                       "camera rolled: \(camNode.eulerAngles)")
        }
    },
    Check("when asked for its view the SceneKit renderer lights the scene with ambient and directional lights") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(spec: defaultSpec(), stripWidth: 1000)
            guard let scene = sceneKitScene(renderer) else {
                try expect(false, "renderer produced no scene")
                return
            }
            let types = scene.rootNode.childNodes.compactMap { $0.light?.type }
            try expect(types.contains(.ambient))
            try expect(types.contains(.directional))
        }
    },
    Check("when asked for its view the SceneKit renderer holds the model locomotive node") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(spec: defaultSpec(), stripWidth: 1000)
            guard let scene = sceneKitScene(renderer) else {
                try expect(false, "renderer produced no scene")
                return
            }
            let loco = scene.rootNode.childNode(
                withName: "model-loco", recursively: true)
            try expect(loco != nil)
        }
    },
    Check("when model cars couple the chain anchors at the loco's rear-bottom in scene units") {
        try MainActor.assumeIsolated {
            // laneHeight 360 doubles locoScale — the design→wrapper-local
            // anchor conversion must hold at any lane scale; dividing by
            // nodeScale only looked right at laneHeight == reference.
            let spec = defaultSpec()
            let renderer = SceneKitRenderer(
                spec: spec, stripWidth: 1000, laneHeight: 360)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 360),
                spec: spec) as? SCNView,
                  let loco = view.scene?.rootNode.childNode(
                      withName: "model-loco", recursively: true),
                  let chain = loco.childNode(
                      withName: "car-chain", recursively: true)
            else {
                try expect(false, "model loco + car chain missing")
                return
            }
            guard let url = modelAssetURL(named: "loco.usdz"),
                  let loaded = try? ModelAsset.loadTrain(
                      at: url.path,
                      targetHeight: ModelAsset.locomotiveDesignHeight)
            else {
                try expect(false, "bundled loco missing")
                return
            }
            let locoScale = 360 / OverlayGeometry.referenceLaneHeight
            let s = CGFloat(loco.scale.x)
            let wantX = loaded.size.width / 2 * locoScale
            let wantY = -loaded.size.height / 2 * locoScale
            try expect(abs(chain.position.x * s - wantX) < 1,
                       "chain x \(chain.position.x * s) vs \(wantX)")
            try expect(abs(chain.position.y * s - wantY) < 1,
                       "chain y \(chain.position.y * s) vs \(wantY)")
        }
    },
    Check("when the consist rolls the wheelwork spins wheels and drives rods only") {
        try MainActor.assumeIsolated {
            let spec = defaultSpec()
            let renderer = SceneKitRenderer(spec: spec, stripWidth: 1000)
            guard let scene = sceneKitScene(renderer),
                  let loco = scene.rootNode.childNode(
                      withName: "model-loco", recursively: true)
            else {
                try expect(false, "no model loco in scene")
                return
            }
            var before: [ObjectIdentifier: (String, SCNVector3, SCNVector4)] = [:]
            loco.enumerateChildNodes { node, _ in
                before[ObjectIdentifier(node)] = (
                    node.name ?? "<unnamed>", node.position, node.rotation)
            }
            // Two poses apart so the rig accumulates real distance.
            renderer.render(at: 3)
            renderer.render(at: 4)
            let animated: Set<String> = [
                "driver_1", "driver_2", "driver_3",
                "wheelset_1", "wheelset_2", "wheelset_3",
                "coupling_rod_L", "coupling_rod_R",
                "crosshead_L", "crosshead_R",
                "connecting_rod_L", "connecting_rod_R",
            ]
            var moved: [String] = []
            loco.enumerateChildNodes { node, _ in
                guard let b = before[ObjectIdentifier(node)] else { return }
                if node.position.x != b.1.x || node.position.y != b.1.y
                    || node.position.z != b.1.z
                    || node.rotation.w != b.2.w || node.rotation.x != b.2.x {
                    moved.append(b.0)
                }
            }
            let stray = moved.filter { !animated.contains($0) }
            try expect(stray.isEmpty,
                       "unexpected nodes moved: \(stray)")
            let missing = animated.filter { !moved.contains($0) }
            try expect(missing.isEmpty,
                       "rigged nodes stayed static: \(missing)")
            // The coupling rod orbits at the crank radius: its pivot
            // distance to the driven axle stays constant.
            guard let axle = loco.childNode(
                      withName: "driver_2", recursively: true),
                  let rod = loco.childNode(
                      withName: "coupling_rod_L", recursively: true)
            else { return }
            let dy = rod.position.y - axle.position.y
            let dz = rod.position.z - axle.position.z
            let r = sqrt(dy * dy + dz * dz)
            try expect(r > 0.2 && r < 0.5,
                       "crank radius drifted: \(r)")
            // Connecting rod stays nearly horizontal — long rods only
            // tilt a few degrees off the crosshead pin.
            if let con = loco.childNode(
                withName: "connecting_rod_L", recursively: true) {
                try expect(abs(con.rotation.w) < 0.3,
                           "connecting rod tilted \(con.rotation.w) rad")
            }
            // Front faces travel (-x): cylinders/crossheads sit ahead
            // of the driven axle. A +x crosshead means the model is
            // running backwards (the bundled assets are authored
            // facing +x and yaw π at load).
            if let cross = loco.childNode(
                    withName: "crosshead_L", recursively: true) {
                try expect(cross.worldPosition.x < axle.worldPosition.x,
                           "loco faces +x — cylinders trail the drivers")
            }
        }
    },
    Check("when the scene camera is angled it swings toward the loco's front") {
        try MainActor.assumeIsolated {
            @MainActor func cameraX(_ args: [String]) throws -> CGFloat {
                let spec: RunSpec
                switch RunSpec.parse(args) {
                case .success(let s): spec = s
                case .failure(let e):
                    throw CheckFailure(message: "spec failed: \(e)")
                }
                let renderer = SceneKitRenderer(spec: spec, stripWidth: 1000)
                guard let scene = (renderer.makeView(
                    in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                    spec: spec) as? SCNView)?.scene,
                      let cam = scene.rootNode.childNode(
                          withName: "camera", recursively: false)
                else {
                    throw CheckFailure(message: "no camera node in scene")
                }
                return cam.position.x
            }
            // Center is x=500; a positive azimuth swings toward -x.
            let angled = try cameraX(["sl"])
            try expect(angled < 500,
                       "default angle did not swing toward the front")
            try expectEqual(try cameraX(["sl", "--angle", "0"]), 500)
        }
    },
    Check("when stepped the SceneKit renderer moves the train right-to-left and reports finished") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(spec: defaultSpec(), stripWidth: 1000)
            guard let scene = sceneKitScene(renderer),
                  let loco = scene.rootNode.childNode(
                    withName: "model-loco", recursively: true) else {
                try expect(false, "renderer produced no train node")
                return
            }
            try expect(renderer.step(to: 0))
            renderer.render(at: 1)
            let earlyX = loco.position.x
            renderer.render(at: 7)
            try expect(loco.position.x < earlyX)
            try expect(!renderer.step(to: renderer.duration + 1))
        }
    },
    Check("when the locomotive asset cannot be loaded the renderer still builds an empty train node") {
        try MainActor.assumeIsolated {
            let spec: RunSpec
            switch RunSpec.parse(
                ["sl", "--model", "/nonexistent-dir/nope.usdz"]) {
            case .success(let parsed): spec = parsed
            case .failure(let error):
                fatalError("bad-model spec must parse: \(error)")
            }
            let renderer = SceneKitRenderer(spec: spec, stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: spec) as? SCNView,
                let scene = view.scene else {
                try expect(false, "renderer produced no scene")
                return
            }
            let loco = scene.rootNode.childNode(
                withName: "model-loco", recursively: true)
            try expect(loco != nil, "no placeholder train node")
            // The fallback carries no asset content — an empty node,
            // not a crash and not a partial consist.
            try expect(loco?.childNodes.isEmpty == true,
                       "placeholder train should be empty")
        }
    },
    Check("when asked for a snapshot the SceneKit renderer renders the lit locomotive over transparency") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(spec: defaultSpec(), stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: defaultSpec()) as? SCNView else {
                try expect(false, "view is not an SCNView")
                return
            }
            renderer.render(at: 4) // mid-crossing: the train is on screen
            let image = view.snapshot()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else {
                try expect(false, "SCNView produced no snapshot")
                return
            }
            // The background is fully transparent, so every opaque
            // pixel belongs to the train — count them at any snapshot
            // scale.
            var lit = 0
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                    if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 {
                        lit += 1
                    }
                }
            }
            try expect(lit > 2000, "only \(lit) lit pixels in the snapshot")
        }
    },
]
