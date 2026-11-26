import AppKit
import QuartzCore
import SceneKit
import SLCore
import SLTestKit
import TrainScene

private func defaultSpec() -> RunSpec {
    switch RunSpec.parse(["sl"]) {
    case .success(let spec): return spec
    case .failure(let error): fatalError("default spec must parse: \(error)")
    }
}

/// Drops a bare `smoke` anchor into the train node — the ghost-steam
/// gate only fires when the loco carries one (the bundled model has
/// none while chimney smoke stays disabled).
@MainActor
private func addSmokeAnchor(to scene: SCNScene) {
    guard let train = scene.rootNode.childNode(
        withName: "model-loco", recursively: true) else { return }
    let smoke = SCNNode()
    smoke.name = "smoke"
    train.addChildNode(smoke)
}

private func keyframeValues(_ controller: SCNParticlePropertyController?)
    -> [Double] {
    guard let animation = controller?.animation as? CAKeyframeAnimation,
          let values = animation.values as? [NSNumber] else { return [] }
    return values.map(\.doubleValue)
}

public let ghostSteamChecks: [Check] = [
    Check("when ghost steam is emitted it is a translucent world-space trail that fades out") {
        try MainActor.assumeIsolated {
            let node = ghostSteamEmitter()
            try expect(node.name == "ghost-steam",
                       "emitter not named ghost-steam")
            guard let system = node.particleSystems?.first else {
                throw CheckFailure(message: "ghost emitter has no particle system")
            }
            try expect(system.birthRate > 0, "ghost steam never emits")
            // World space: puffs linger where emitted instead of
            // riding the (already gone) train node.
            try expect(system.isLocal == false,
                       "ghost puffs locked to the emitter node")
            try expect(system.emittingDirection.y > 0.5,
                       "trail does not drift up")
            try expect(system.particleLifeSpan >= 1,
                       "puffs die before the ~1s trail reads")
            let opacity = keyframeValues(system.propertyControllers?[.opacity])
            try expect(opacity.last == 0, "trail never fades out")
            try expect((opacity.max() ?? 1) <= 0.7,
                       "trail too opaque: peak \(opacity.max() ?? -1)")
        }
    },
    Check("when the consist clears the lane the renderer holds the scene for the ghost steam trail") {
        try MainActor.assumeIsolated {
            let spec = defaultSpec()
            let renderer = SceneKitRenderer(spec: spec, stripWidth: 1000)
            guard let scene = (renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: spec) as? SCNView)?.scene else {
                throw CheckFailure(message: "renderer produced no scene")
            }
            addSmokeAnchor(to: scene)
            // Mid-run there is nothing to hold for.
            try expectEqual(renderer.postExitRemaining(at: 0), 0)
            try expectEqual(renderer.postExitRemaining(at: 4), 0)
            // Step to the exit frame, then into the trail.
            var t: TimeInterval = 0
            while renderer.step(to: t) { t += 0.1 }
            let exit = t
            try expect(renderer.postExitHold >= 1.0,
                       "hold shorter than the ~1s trail: \(renderer.postExitHold)")
            // exit+0.5s: trail still dissipating.
            try expect(renderer.postExitRemaining(at: exit + 0.5) > 0,
                       "trail already decayed at exit+0.5s")
            // Past the hold the trail is gone and the fade may start.
            try expectEqual(
                renderer.postExitRemaining(
                    at: exit + renderer.postExitHold + 0.1), 0)
        }
    },
    Check("when the train exits a ghost steam emitter drops where the train was and stops firing") {
        try MainActor.assumeIsolated {
            let spec = defaultSpec()
            let renderer = SceneKitRenderer(spec: spec, stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: spec) as? SCNView, let scene = view.scene else {
                throw CheckFailure(message: "renderer produced no scene")
            }
            addSmokeAnchor(to: scene)
            // The exit frame (duration 8): the emitter drops and
            // still fires — the trail is being born.
            renderer.step(to: 8)
            guard let ghost = scene.rootNode.childNode(
                withName: "ghost-steam", recursively: true),
                  let system = ghost.particleSystems?.first else {
                throw CheckFailure(message: "no ghost-steam emitter after exit")
            }
            // The trail hangs over the lane's left end — where the
            // consist exited — not back at center-lane or offscreen.
            try expect(ghost.position.x > 80 && ghost.position.x < 320,
                       "emitter not at the exit: x=\(ghost.position.x)")
            try expect(system.birthRate > 0,
                       "emitter silent at the exit frame")
            // 0.5s into the trail: past the emit window, only the
            // puffs' own decay remains.
            renderer.step(to: 8.5)
            try expectEqual(system.birthRate, 0)
        }
    },
    Check("when the loco carries no smoke anchor no ghost steam drops and the hold is zero") {
        try MainActor.assumeIsolated {
            let spec = defaultSpec()
            let renderer = SceneKitRenderer(spec: spec, stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: spec) as? SCNView, let scene = view.scene else {
                throw CheckFailure(message: "renderer produced no scene")
            }
            // Bundled model has no chimney smoke — so nothing may
            // spawn a trail out of thin air after the exit.
            try expectEqual(renderer.postExitHold, 0)
            renderer.step(to: 8)
            try expect(
                scene.rootNode.childNode(
                    withName: "ghost-steam", recursively: true) == nil,
                "ghost steam dropped with no smoke source")
        }
    },
    Check("when a renderer has no post-exit scene the hold defaults to zero") {
        try MainActor.assumeIsolated {
            let renderer = PlaceholderRenderer(
                spec: defaultSpec(), stripWidth: 1000)
            try expectEqual(renderer.postExitHold, 0)
            try expectEqual(renderer.postExitRemaining(at: 99), 0)
        }
    },
]

/// Renders the scene to a quantized RGB grid (stride 4) so checks can
/// diff two frozen moments pixel-wise — `snapshot()` fills transparent
/// pixels with an opaque light backing, so only *differences* between
/// two renders isolate scene content.
@MainActor
private func snapshotGrid(at t: TimeInterval) throws -> [UInt32] {
    let spec = defaultSpec()
    let renderer = SceneKitRenderer(spec: spec, stripWidth: 1000)
    guard let view = renderer.makeView(
        in: NSRect(x: 0, y: 0, width: 1000, height: 180),
        spec: spec) as? SCNView else {
        throw CheckFailure(message: "no view")
    }
    if let scene = view.scene { addSmokeAnchor(to: scene) }
    renderer.render(at: t)
    guard let tiff = view.snapshot().tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        throw CheckFailure(message: "no snapshot")
    }
    var grid: [UInt32] = []
    grid.reserveCapacity(12000)
    for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            guard let c = rep.colorAt(x: x, y: y),
                  let rgb = c.usingColorSpace(.sRGB) else {
                grid.append(0)
                continue
            }
            let r = UInt32(max(0, min(255, Int(rgb.redComponent * 255))))
            let g = UInt32(max(0, min(255, Int(rgb.greenComponent * 255))))
            let b = UInt32(max(0, min(255, Int(rgb.blueComponent * 255))))
            grid.append((r << 16) | (g << 8) | b)
        }
    }
    return grid
}

/// Samples of the stride-4 grid whose x is under `xLimit`.
private func laneLeftDiff(_ a: [UInt32], _ b: [UInt32],
                          xLimit: Int = 400) -> Int {
    var diff = 0
    for i in 0..<min(a.count, b.count) {
        guard (i % 250) * 4 < xLimit else { continue }
        let dr = Int((a[i] >> 16) & 0xFF) - Int((b[i] >> 16) & 0xFF)
        let dg = Int((a[i] >> 8) & 0xFF) - Int((b[i] >> 8) & 0xFF)
        let db = Int(a[i] & 0xFF) - Int(b[i] & 0xFF)
        if abs(dr) + abs(dg) + abs(db) > 60 { diff += 1 }
    }
    return diff
}

public let ghostSteamSnapshotChecks: [Check] = [
    Check("when frozen at exit+0.5 the rendered scene shows the trail over the lane without the train") {
        try MainActor.assumeIsolated {
            // 0.5s: the consist is mid-lane, far right — lane-left is
            // empty lane. 8.5s (exit+0.5): consist gone, ghost steam
            // hanging over the lane's left end.
            let before = try snapshotGrid(at: 0.5)
            let after = try snapshotGrid(at: 8.5)
            let diff = laneLeftDiff(before, after)
            try expect(diff > 100,
                       "no trail signature over the lane-left: \(diff)")
        }
    },
]
