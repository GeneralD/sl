import AppKit
import SceneKit
import SLCore
import SLTestKit
import TrainScene

private func discoSpec() -> RunSpec {
    switch RunSpec.parse(["sl", "-d"]) {
    case .success(let spec): return spec
    case .failure(let error): fatalError("-d spec must parse: \(error)")
    }
}

/// First material-bearing descendant of the model — the `-d` tint
/// target `locoMaterials` collects. There is no `boiler` node name on
/// a USDZ asset, so pick whatever paints first.
private func firstMaterial(in node: SCNNode) -> SCNMaterial? {
    if let material = node.geometry?.materials.first {
        return material
    }
    for child in node.childNodes {
        if let material = firstMaterial(in: child) { return material }
    }
    return nil
}

private func hue(of color: Any?) -> CGFloat? {
    guard let ns = color as? NSColor,
          let converted = ns.usingColorSpace(.deviceRGB) else { return nil }
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    converted.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return h
}

private func lightColors(_ scene: SCNScene) -> (key: NSColor?, ambient: NSColor?) {
    var key: NSColor?, ambient: NSColor?
    for node in scene.rootNode.childNodes {
        guard let light = node.light else { continue }
        switch light.type {
        case .directional: key = light.color as? NSColor
        case .ambient: ambient = light.color as? NSColor
        default: break
        }
    }
    return (key, ambient)
}

public let discoChecks: [Check] = [
    Check("when -d is on two shots at different times show different loco hues") {
        try MainActor.assumeIsolated {
            let timeline = DiscoTimeline()
            let h1 = timeline.hue(at: 0)
            let h2 = timeline.hue(at: timeline.huePeriod / 2)
            try expect(abs(h2 - h1) > 0.25,
                       "hues too close: \(h1) vs \(h2)")

            // One renderer, two shots: the material hue must differ.
            let renderer = SceneKitRenderer(spec: discoSpec(), stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: discoSpec()) as? SCNView,
                let scene = view.scene,
                let loco = scene.rootNode.childNode(
                    withName: "model-loco", recursively: true),
                let material = firstMaterial(in: loco) else {
                try expect(false, "disco renderer produced no material")
                return
            }
            renderer.render(at: 0)
            let h0 = hue(of: material.diffuse.contents)
            renderer.render(at: timeline.huePeriod / 2)
            let h1b = hue(of: material.diffuse.contents)
            guard let h0, let h1b else {
                try expect(false, "disco material has no readable hue")
                return
            }
            try expect(abs(h1b - h0) > 0.05,
                       "two disco shots show the same hue: \(h0) vs \(h1b)")
        }
    },
    Check("when -d is on the scene lights flash alternating colors") {
        try MainActor.assumeIsolated {
            // One renderer across two beats: key and ambient lights take
            // opposite palette colors and swap on the next beat.
            // t=0 -> beat 0; t=0.75 at rate 2 -> floor(1.5)=1 -> swapped.
            let renderer = SceneKitRenderer(spec: discoSpec(), stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: discoSpec()) as? SCNView,
                let scene = view.scene else {
                try expect(false, "disco renderer produced no scene")
                return
            }
            renderer.render(at: 0)
            let (key0, ambient0) = lightColors(scene)
            renderer.render(at: 0.75)
            let (key1, ambient1) = lightColors(scene)
            try expect(key0 != nil && ambient0 != nil,
                       "disco lights have no color")
            try expect(key0 != ambient0,
                       "both lights share one color — not alternating")
            try expect(key1 != ambient1,
                       "lights stopped alternating on the next beat")
            try expect(key1 != key0 || ambient1 != ambient0,
                       "light colors did not alternate between beats")
        }
    },
    Check("when -d is on the train scale pulse stays within a modest amplitude") {
        try MainActor.assumeIsolated {
            let timeline = DiscoTimeline()
            // Sample a full flash period; deviation from 1 must stay small.
            var maxDev: Double = 0
            var t: TimeInterval = 0
            while t <= 1.0 / timeline.flashRate {
                maxDev = max(maxDev, abs(timeline.scale(at: t) - 1))
                t += 1.0 / 240
            }
            try expect(maxDev <= 0.15,
                       "scale pulse amplitude \(maxDev) exceeds modest bound")

            // And the renderer actually applies it: peak of the sine is
            // at t = 1/(4*flashRate) = 0.125 for the default rate. The
            // wrapper's base scale is the model normalization ×
            // `locoScale`, so assert the pulse as a ratio, not an
            // absolute.
            let renderer = SceneKitRenderer(spec: discoSpec(), stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: discoSpec()) as? SCNView,
                let scene = view.scene,
                let train = scene.rootNode.childNode(
                    withName: "model-loco", recursively: true) else {
                try expect(false, "disco renderer produced no train")
                return
            }
            renderer.render(at: 0)
            let rest = train.scale.x
            renderer.render(at: 0.125)
            let pulsed = train.scale.x / rest - 1
            try expect(pulsed > 0.01,
                       "train scale never pulsed: \(pulsed)")
            try expect(pulsed <= 0.15,
                       "pulse too large: \(pulsed)")
        }
    },
    Check("when -d is on the flash rate never exceeds three per second") {
        let timeline = DiscoTimeline()
        try expect(timeline.flashRate <= DiscoTimeline.maxFlashRate)
        try expect(DiscoTimeline.maxFlashRate <= 3)
        // A hostile requested rate is clamped to the ceiling.
        try expect(DiscoTimeline(flashRate: 60).flashRate
            == DiscoTimeline.maxFlashRate)
        // Count actual color flips in a one-second window at 120 Hz.
        var flips = 0
        var prev = timeline.lightIndex(at: 0)
        var t = 1.0 / 120
        while t <= 1.0 {
            let idx = timeline.lightIndex(at: t)
            if idx != prev { flips += 1 }
            prev = idx
            t += 1.0 / 120
        }
        try expect(flips <= 3,
                   "\(flips) light flips in one second exceeds seizure-safe bound")
    },
    Check("when -d is off the renderer leaves lights and scale untouched") {
        try MainActor.assumeIsolated {
            guard case .success(let spec) = RunSpec.parse(["sl"]) else {
                try expect(false, "default spec must parse")
                return
            }
            let renderer = SceneKitRenderer(spec: spec, stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: spec) as? SCNView,
                let scene = view.scene,
                let train = scene.rootNode.childNode(
                    withName: "model-loco", recursively: true) else {
                try expect(false, "plain renderer produced no scene")
                return
            }
            renderer.render(at: 0.125)
            let scaleA = train.scale.x
            renderer.render(at: 0.75)
            try expectEqual(train.scale.x, scaleA)
            let (key, ambient) = lightColors(scene)
            // Default rig: lights keep their authored colors (nil color
            // means SceneKit default white — both equal, never swapped).
            try expect(key == ambient || (key == nil && ambient == nil))
        }
    },
]
