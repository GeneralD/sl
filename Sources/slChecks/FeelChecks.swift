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

/// World-space y-extent of the locomotive CONTENT: `boundingBox` is
/// local-space and excludes the node's own scale, so corners are
/// converted through the world transform. The `car-chain` and the
/// effect anchors (`chimney`/`headlight`/`screamers`) are skipped —
/// the chain counter-scales against `locoScale`, so including it
/// would make the measured height depend on the car count.
@MainActor
private func worldHeight(of node: SCNNode?) -> CGFloat {
    guard let node else { return 0 }
    let skip: Set<String> = ["car-chain", "chimney", "headlight",
                             "screamers"]
    var lo = CGFloat.greatestFiniteMagnitude
    var hi = -CGFloat.greatestFiniteMagnitude
    for child in node.childNodes where !skip.contains(child.name ?? "") {
        let b = child.boundingBox
        let cLo = child.convertPosition(
            SCNVector3(b.min.x, b.min.y, b.min.z), to: nil)
        let cHi = child.convertPosition(
            SCNVector3(b.max.x, b.max.y, b.max.z), to: nil)
        lo = min(lo, CGFloat(min(cLo.y, cHi.y)))
        hi = max(hi, CGFloat(max(cLo.y, cHi.y)))
    }
    guard lo.isFinite, hi.isFinite else { return 0 }
    return hi - lo
}

public let feelChecks: [Check] = [
    Check("when the spec carries -l the locomotive and cars render at the little scale") {
        try MainActor.assumeIsolated {
            guard let full = scene(for: ["sl"]),
                  let little = scene(for: ["sl", "-l"]),
                  let fullLoco = full.rootNode.childNode(
                    withName: "model-loco", recursively: true),
                  let littleLoco = little.rootNode.childNode(
                    withName: "model-loco", recursively: true),
                  let chain = little.rootNode.childNode(
                    withName: "car-chain", recursively: true) else {
                try expect(false, "renderer produced no train scene")
                return
            }
            let ratio = worldHeight(of: littleLoco)
                / worldHeight(of: fullLoco)
            try expect(abs(ratio - 0.6) < 0.02,
                       "little/full height ratio \(ratio), want ~0.6")
            // The coupled cars shrink with the loco: the tender's
            // bounding-box height follows the same 0.6 factor.
            let littleTender = chain.childNode(
                withName: "model-tender", recursively: false)
            let fullTender = full.rootNode.childNode(
                withName: "car-chain", recursively: true)?
                .childNode(withName: "model-tender", recursively: false)
            let carRatio = worldHeight(of: littleTender)
                / worldHeight(of: fullTender)
            try expect(abs(carRatio - 0.6) < 0.05,
                       "little/full tender ratio \(carRatio), want ~0.6")
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
