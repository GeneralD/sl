import AppKit
import SceneKit
import SLCore
import SLTestKit
import TrainScene

private func withRendererEnv<T>(_ value: String?, _ body: () throws -> T) rethrows -> T {
    let had = getenv("SL_RENDERER")
    let saved = had.map { String(cString: $0) }
    if let value { setenv("SL_RENDERER", value, 1) } else { unsetenv("SL_RENDERER") }
    defer {
        if let saved { setenv("SL_RENDERER", saved, 1) } else { unsetenv("SL_RENDERER") }
    }
    return try body()
}

public let sceneKitChecks: [Check] = [
    Check("when SL_RENDERER is unset the factory returns the placeholder renderer") {
        try MainActor.assumeIsolated {
            let renderer = withRendererEnv(nil) {
                RendererFactory.make(spec: RunSpec.parse(["sl"]), stripWidth: 1000)
            }
            try expect(renderer is PlaceholderRenderer)
        }
    },
    Check("when SL_RENDERER is scenkit the factory returns the SceneKit renderer") {
        try MainActor.assumeIsolated {
            let renderer = withRendererEnv("scenkit") {
                RendererFactory.make(spec: RunSpec.parse(["sl"]), stripWidth: 1000)
            }
            try expect(renderer is SceneKitRenderer)
        }
    },
    Check("when asked for its view the SceneKit renderer returns a clear SCNView") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(spec: RunSpec.parse(["sl"]), stripWidth: 1000)
            let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180), spec: RunSpec.parse(["sl"]))
            try expect(view is SCNView)
            guard let scnView = view as? SCNView else {
                try expect(false, "view is not an SCNView")
                return
            }
            try expect(scnView.layer?.isOpaque == false)
            try expect(scnView.backgroundColor == .clear)
        }
    },
    Check("when stepped past its duration the SceneKit renderer reports finished") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(spec: RunSpec.parse(["sl"]), stripWidth: 1000)
            try expect(renderer.step(to: renderer.duration - 1))
            try expect(!renderer.step(to: renderer.duration + 1))
        }
    },
]
