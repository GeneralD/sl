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

private func find(_ name: String, in node: SCNNode) -> SCNNode? {
    node.childNode(withName: name, recursively: true)
}

/// The smoke particle system hanging off the chimney's "smoke" node.
private func smokeSystem(in loco: SCNNode) -> SCNParticleSystem? {
    guard let smoke = find("smoke", in: loco),
          let chimney = find("chimney", in: loco),
          smoke.parent === chimney else { return nil }
    return smoke.particleSystems?.first
}

private func keyframeValues(_ controller: SCNParticlePropertyController?)
    -> [Double] {
    guard let animation = controller?.animation as? CAKeyframeAnimation,
          let values = animation.values as? [NSNumber] else { return [] }
    return values.map(\.doubleValue)
}

/// A stand-in for the named-node contract `attachLocomotiveEffects`
/// reads: `chimney`, `headlight` and `cab` children with a material —
/// the procedural loco that used to provide them is gone (issue #78),
/// and model runs get theirs from `anchorModelLocomotiveEffects`.
@MainActor
private func fakeLoco() -> SCNNode {
    let loco = SCNNode()
    loco.name = "fake-loco"
    for name in ["chimney", "headlight", "cab"] {
        let node = SCNNode(geometry: SCNBox(
            width: 4, height: 4, length: 4, chamferRadius: 0))
        node.name = name
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.gray
        node.geometry?.materials = [material]
        loco.addChildNode(node)
    }
    return loco
}

public let smokeHeadlightChecks: [Check] = [
    Check("when locomotive effects attach the chimney smoke emitter sits at the rim and emits") {
        try MainActor.assumeIsolated {
            let loco = fakeLoco()
            attachLocomotiveEffects(to: loco)
            guard let smoke = find("smoke", in: loco),
                  let chimney = find("chimney", in: loco),
                  smoke.parent === chimney else {
                throw CheckFailure(message: "no smoke emitter under the chimney")
            }
            try expect(smoke.position.y > 15,
                       "emitter not at chimney rim: y=\(smoke.position.y)")
            let system = smokeSystem(in: loco)
            try expect(system != nil, "emitter carries no particle system")
            try expect((system?.birthRate ?? 0) > 0, "smoke never emits")
            try expect(system?.particleLifeSpan ?? 0 > 1,
                       "puffs die too fast to read")
            // World space: puffs stay where emitted and drift behind.
            try expect(system?.isLocal == false,
                       "smoke locked to the loco instead of drifting")
            try expect(system?.emittingDirection.y ?? 0 > 0.5,
                       "smoke does not rise")
        }
    },
    Check("when locomotive effects attach smoke fades out over each puff's life") {
        try MainActor.assumeIsolated {
            let loco = fakeLoco()
            attachLocomotiveEffects(to: loco)
            guard let system = smokeSystem(in: loco) else {
                throw CheckFailure(message: "no smoke particle system")
            }
            let opacity = keyframeValues(
                system.propertyControllers?[.opacity])
            try expect(opacity.count >= 2, "no opacity controller")
            try expect(opacity.last == 0,
                       "puffs never fade out: \(opacity)")
            // Peak opacity stays low — the lane must not opaque over.
            try expect((opacity.max() ?? 1) <= 0.7,
                       "smoke too opaque: peak \(opacity.max() ?? -1)")
            try expect(!keyframeValues(system.propertyControllers?[.size])
                        .isEmpty,
                       "puffs do not grow over life")
        }
    },
    Check("when locomotive effects attach the headlight carries a beam cone aimed forward") {
        try MainActor.assumeIsolated {
            let loco = fakeLoco()
            attachLocomotiveEffects(to: loco)
            guard let beam = find("headlight-beam", in: loco),
                  let headlight = find("headlight", in: loco),
                  beam.parent === headlight else {
                throw CheckFailure(message: "no beam cone on the headlight")
            }
            try expect(beam.geometry is SCNCone,
                       "beam is not a cone/frustum")
            try expect(beam.position.x < 0,
                       "beam does not reach forward (-x): \(beam.position.x)")
            let material = beam.geometry?.materials.first
            let transparency = material?.transparency ?? 1
            try expect(transparency > 0 && transparency < 1,
                       "beam not translucent: \(transparency)")
        }
    },
    Check("when locomotive effects attach the headlight has a spot light shining forward") {
        try MainActor.assumeIsolated {
            let loco = fakeLoco()
            attachLocomotiveEffects(to: loco)
            guard let spot = find("headlight-spot", in: loco),
                  let headlight = find("headlight", in: loco),
                  spot.parent === headlight else {
                throw CheckFailure(message: "no spot light on the headlight")
            }
            try expect(spot.light?.type == .spot,
                       "headlight light is not a spot")
            // Light travels down the node's -z; yaw π/2 points it -x.
            try expect(abs(spot.eulerAngles.y - .pi / 2) < 0.001,
                       "spot not aimed forward: \(spot.eulerAngles.y)")
        }
    },
    Check("when locomotive effects attach the lamp and cab gain a slight warm emission") {
        try MainActor.assumeIsolated {
            let loco = fakeLoco()
            attachLocomotiveEffects(to: loco)
            for name in ["headlight", "cab"] {
                guard let node = find(name, in: loco),
                      let material = node.geometry?.materials.first
                else {
                    throw CheckFailure(
                        message: "\(name) missing or material-less")
                }
                let intensity = material.emission.intensity
                try expect(intensity > 0 && intensity < 2,
                           "\(name) emission intensity \(intensity)")
            }
        }
    },
    Check("when the smoke sprite draws it paints a soft puff and bare nodes attach cleanly") {
        try MainActor.assumeIsolated {
            let loco = fakeLoco()
            attachLocomotiveEffects(to: loco)
            guard let system = smokeSystem(in: loco),
                  let image = system.particleImage as? NSImage else {
                throw CheckFailure(message: "smoke has no sprite image")
            }
            image.draw(
                in: NSRect(x: 0, y: 0, width: 64, height: 64),
                from: .zero, operation: .sourceOver, fraction: 1)
            // Named nodes without geometry take the no-material path.
            let bare = SCNNode()
            attachLocomotiveEffects(to: bare)
            for name in ["headlight", "cab"] {
                let node = SCNNode()
                node.name = name
                bare.addChildNode(node)
            }
            attachLocomotiveEffects(to: bare)
        }
    },
    Check("when the SceneKit renderer builds its view chimney smoke and headlight beam ride along") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(
                spec: defaultSpec(), stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: defaultSpec()) as? SCNView,
                  let scene = view.scene else {
                throw CheckFailure(message: "renderer produced no scene")
            }
            let loco = scene.rootNode.childNode(
                withName: "model-loco", recursively: true)
            try expect(loco != nil, "no locomotive node in scene")
            try expect(find("smoke", in: loco!) != nil,
                       "smoke missing from rendered loco")
            try expect(find("headlight-beam", in: loco!) != nil,
                       "headlight beam missing from rendered loco")
        }
    }
]
