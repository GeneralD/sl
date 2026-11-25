import AppKit
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
            // Elevated straight toward the viewer (+y, +z), no yaw —
            // pitched down, level horizon.
            try expect(camNode.position.x == 500)
            try expect(camNode.position.y == 990)
            try expect(camNode.position.z == 1200)
            try expect(camNode.eulerAngles.x < -0.3,
                       "camera not pitched down: \(camNode.eulerAngles)")
            try expect(abs(camNode.eulerAngles.y) < 0.001,
                       "camera yawed off the lane: \(camNode.eulerAngles)")
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
