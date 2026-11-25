import SceneKit
import SLCore
import SLTestKit
import TrainScene

/// `RunSpec.parse` returns Result; unwrap or die — a bad fixture is a
/// broken check, not a test failure.
private func spec(_ args: [String]) -> RunSpec {
    switch RunSpec.parse(args) {
    case .success(let s): return s
    case .failure(let e): fatalError("fixture must parse: \(e)")
    }
}

/// Builds the SceneKit renderer's scene for `args`, the way `sl` wires
/// it (spec → renderer → makeView).
@MainActor
private func scene(for args: [String]) -> SCNScene? {
    let run = spec(args)
    let renderer = SceneKitRenderer(spec: run, stripWidth: 1000)
    guard let view = renderer.makeView(
        in: NSRect(x: 0, y: 0, width: 1000, height: 180),
        spec: run) as? SCNView else { return nil }
    return view.scene
}

@MainActor
private func renderer(for args: [String]) -> SceneKitRenderer {
    SceneKitRenderer(spec: spec(args), stripWidth: 1000)
}

private func height(of node: SCNNode?) -> CGFloat {
    guard let node else { return 0 }
    let b = node.boundingBox
    return CGFloat(b.max.y - b.min.y)
}

public let feelChecks: [Check] = [
    Check("when the spec carries -l the locomotive and cars render at the little scale") {
        try MainActor.assumeIsolated {
            guard let full = scene(for: ["sl"]),
                  let little = scene(for: ["sl", "-l"]),
                  let fullLoco = full.rootNode.childNode(
                    withName: "procedural-locomotive", recursively: true),
                  let littleLoco = little.rootNode.childNode(
                    withName: "procedural-locomotive", recursively: true),
                  let chain = little.rootNode.childNode(
                    withName: "car-chain", recursively: true) else {
                try expect(false, "renderer produced no train scene")
                return
            }
            let ratio = height(of: littleLoco) / height(of: fullLoco)
            try expect(abs(ratio - 0.6) < 0.02,
                       "little/full height ratio \(ratio), want ~0.6")
            try expect(abs(chain.scale.x - 0.6) < 0.001,
                       "car chain scale \(chain.scale.x), want 0.6")
        }
    },
    Check("when the spec carries -w the crossing duration shrinks by the speed factor") {
        try MainActor.assumeIsolated {
            let calm = renderer(for: ["sl"]).duration
            let windy = renderer(for: ["sl", "-w"]).duration
            try expect(windy < calm,
                       "windy duration \(windy) not shorter than \(calm)")
            try expect(abs(windy * 1.5 - calm) < 0.001,
                       "windy duration \(windy) is not calm/1.5")
        }
    },
    Check("when the spec carries -7 the rendered scene couples seven cars") {
        try MainActor.assumeIsolated {
            guard let scene = scene(for: ["sl", "-7"]),
                  let chain = scene.rootNode.childNode(
                    withName: "car-chain", recursively: true) else {
                try expect(false, "no car chain in scene")
                return
            }
            try expect(chain.childNodes.count == 7,
                       "found \(chain.childNodes.count) cars")
        }
    },
]
