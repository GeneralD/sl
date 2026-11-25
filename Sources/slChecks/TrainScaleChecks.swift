import AppKit
import OverlayKit
import SceneKit
import SLCore
import SLTestKit
import TrainScene

private func spec(_ args: [String]) throws -> RunSpec {
    switch RunSpec.parse(args) {
    case .success(let spec): return spec
    case .failure(let error):
        try expect(false, "parse failed: \(error.message)")
        fatalError("unreachable: expect(false) always throws")
    }
}

private func parseFails(_ args: [String]) throws {
    if case .success = RunSpec.parse(args) {
        try expect(false, "expected parse failure for \(args)")
    }
}

/// The rendered loco CONTENT's world-space height in scene units —
/// `boundingBox` is local-space and excludes the wrapper's own
/// scale, so corners are converted through the world transform. The
/// `car-chain` and effect anchors are skipped: the chain
/// counter-scales against `locoScale`, so including it would make
/// the height depend on the car count.
@MainActor
private func locoHeight(spec: RunSpec, laneHeight: CGFloat) throws -> CGFloat {
    let renderer = SceneKitRenderer(
        spec: spec, stripWidth: 1000, laneHeight: laneHeight)
    guard let view = renderer.makeView(
        in: NSRect(x: 0, y: 0, width: 1000, height: laneHeight),
        spec: spec) as? SCNView,
          let scene = view.scene,
          let loco = scene.rootNode.childNode(
            withName: "model-loco", recursively: true)
    else {
        throw CheckFailure(message: "no locomotive in scene")
    }
    let skip: Set<String> = ["car-chain", "chimney", "headlight",
                             "screamers"]
    var lo = CGFloat.greatestFiniteMagnitude
    var hi = -CGFloat.greatestFiniteMagnitude
    for child in loco.childNodes where !skip.contains(child.name ?? "") {
        let box = child.boundingBox
        let cLo = child.convertPosition(
            SCNVector3(box.min.x, box.min.y, box.min.z), to: nil)
        let cHi = child.convertPosition(
            SCNVector3(box.max.x, box.max.y, box.max.z), to: nil)
        lo = min(lo, CGFloat(min(cLo.y, cHi.y)))
        hi = max(hi, CGFloat(max(cLo.y, cHi.y)))
    }
    guard lo.isFinite, hi.isFinite else {
        throw CheckFailure(message: "locomotive has no content bounds")
    }
    return hi - lo
}

public let trainScaleChecks: [Check] = [
    Check("when no --scale is given the train scale defaults to 1") {
        let s = try spec(["sl"])
        try expectEqual(s.scale, 1.0)
    },
    Check("when invoked with --scale and a factor it records the scale") {
        try expectEqual(try spec(["sl", "--scale", "2"]).scale, 2.0)
        try expectEqual(try spec(["sl", "--scale", "0.5"]).scale, 0.5)
    },
    Check("when invoked with --scale=factor it records the scale") {
        try expectEqual(try spec(["sl", "--scale=1.75"]).scale, 1.75)
    },
    Check("when invoked with --scale and a non-positive or non-numeric value it reports a parse error") {
        try parseFails(["sl", "--scale", "0"])
        try parseFails(["sl", "--scale", "-2"])
        try parseFails(["sl", "--scale", "big"])
        try parseFails(["sl", "--scale"])
    },
    Check("when the lane height is computed from the screen height it is the lane fraction of it") {
        try expectEqual(
            OverlayGeometry.laneHeight(onScreenHeight: 982),
            982 * OverlayGeometry.laneFraction)
        try expect(OverlayGeometry.laneFraction > 0.3,
                   "lane fraction \(OverlayGeometry.laneFraction) too small")
    },
    Check("when the renderer is built for the grown lane the locomotive fills a large share of the screen height") {
        try MainActor.assumeIsolated {
            // A 982pt-tall display → 589pt lane; the D51 design height
            // is 150pt, so the rendered loco lands near half the screen.
            let laneH = OverlayGeometry.laneHeight(onScreenHeight: 982)
            let h = try locoHeight(
                spec: spec(["sl"]), laneHeight: laneH)
            try expect(h > 982 * 0.33,
                       "loco height \(h) under a third of the screen")
        }
    },
    Check("when --scale doubles the train the rendered locomotive is twice as tall") {
        try MainActor.assumeIsolated {
            let base = try locoHeight(spec: spec(["sl"]), laneHeight: 180)
            let big = try locoHeight(
                spec: spec(["sl", "--scale", "2"]), laneHeight: 180)
            try expect(abs(big / base - 2) < 0.15,
                       "scale 2 gave \(big / base)x height, want ~2x")
        }
    },
    Check("when the lane grows the locomotive grows by the same ratio") {
        try MainActor.assumeIsolated {
            let small = try locoHeight(spec: spec(["sl"]), laneHeight: 180)
            let big = try locoHeight(spec: spec(["sl"]), laneHeight: 540)
            try expect(abs(big / small - 3) < 0.15,
                       "3x lane gave \(big / small)x height, want ~3x")
        }
    },
    Check("when ghost steam is emitted at a larger scale its shell widens with the train") {
        try MainActor.assumeIsolated {
            let small = ghostSteamEmitter(scale: 1)
            let big = ghostSteamEmitter(scale: 3)
            guard let sBox = small.geometry as? SCNBox,
                  let bBox = big.geometry as? SCNBox else {
                throw CheckFailure(message: "ghost emitters lost their shell")
            }
            try expect(bBox.width > sBox.width * 2.5,
                       "ghost shell did not follow scale")
        }
    },
    Check("when asked for the usage it lists --scale") {
        try expect(RunSpec.usage().contains("--scale"),
                   "usage() lacks --scale")
    },
]
