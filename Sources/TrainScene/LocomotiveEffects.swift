import AppKit
import QuartzCore
import SceneKit

/// Atmosphere layered onto the procedural locomotive's named nodes:
/// chimney smoke (an `SCNParticleSystem` of soft puffs that drift,
/// grow and fade), the headlight's emissive beam cone + spot light,
/// and a faint warm emission inside the cab. Everything is looked up
/// by node name, so a `--model` asset without those names gets
/// nothing. `scale` is the `-l` miniature factor so effects shrink
/// with the loco.
@MainActor
public func attachLocomotiveEffects(to loco: SCNNode, scale: CGFloat = 1) {
    if let chimney = loco.childNode(withName: "chimney", recursively: true) {
        chimney.addChildNode(smokeEmitter(scale: scale))
    }
    if let headlight = loco.childNode(withName: "headlight", recursively: true) {
        lampGlow(headlight)
        headlight.addChildNode(headlightBeam(scale: scale))
        headlight.addChildNode(headlightSpot())
    }
    if let cab = loco.childNode(withName: "cab", recursively: true) {
        cabGlow(cab)
    }
}

// MARK: - Chimney smoke

/// An empty-looking node at the chimney rim carrying the particle
/// system. The sub-pixel sphere gives `birthLocation = .surface` real
/// geometry to emit from; its material is fully transparent.
private func smokeEmitter(scale s: CGFloat) -> SCNNode {
    let node = SCNNode()
    node.name = "smoke"
    node.position = SCNVector3(0, Float(19 * s), 0)

    let shell = SCNSphere(radius: 1.5 * s)
    let shellMaterial = SCNMaterial()
    shellMaterial.lightingModel = .constant
    shellMaterial.diffuse.contents = NSColor.clear
    shellMaterial.transparency = 0
    shell.materials = [shellMaterial]
    node.geometry = shell

    node.addParticleSystem(chimneySmoke(scale: s))
    return node
}

/// Light-gray puffs that rise, drift backwards (+x, opposite the
/// -x run direction) and fade out — world-space (`isLocal = false`)
/// so they linger where emitted instead of riding the loco.
private func chimneySmoke(scale s: CGFloat) -> SCNParticleSystem {
    let smoke = SCNParticleSystem()
    smoke.birthRate = 14
    // birthRate counts particles per emissionDuration, and `loops`
    // (default on) re-fires every second — a continuous ~14 puffs/s.
    smoke.emissionDuration = 1
    smoke.warmupDuration = 1.4    // puffs already aloft in frame one
    smoke.particleLifeSpan = 2.6
    smoke.particleLifeSpanVariation = 0.7
    smoke.particleVelocity = 18
    smoke.particleVelocityVariation = 6
    smoke.emittingDirection = SCNVector3(0.35, 1, 0)
    smoke.spreadingAngle = 28
    smoke.dampingFactor = 0.5
    smoke.particleColor = NSColor(calibratedWhite: 0.72, alpha: 1)
    smoke.particleColorVariation = SCNVector4(0.06, 0.06, 0.06, 0.15)
    smoke.particleSize = 8 * s
    smoke.particleSizeVariation = 3 * s
    smoke.particleImage = smokePuff()
    smoke.blendMode = .alpha
    smoke.sortingMode = .distance
    smoke.isLightingEnabled = false
    smoke.isLocal = false
    smoke.isAffectedByGravity = false
    smoke.propertyControllers = [
        .opacity: fadeController(),
        .size: growController(),
    ]
    return smoke
}

/// Fade in, hold, fade out over each puff's life. Peak opacity stays
/// well under 1 so the lane underneath never gets opaqued.
private func fadeController() -> SCNParticlePropertyController {
    let animation = CAKeyframeAnimation()
    animation.values = [0.0, 0.55, 0.5, 0.0]
    return SCNParticlePropertyController(animation: animation)
}

/// Puffs billow as they rise. The size controller's animation values
/// multiply `particleSize` (verified against `SCNRenderer` output), so
/// these are growth factors, not point sizes.
private func growController() -> SCNParticlePropertyController {
    let animation = CAKeyframeAnimation()
    animation.values = [0.6, 1.0, 1.8, 2.6].map {
        NSNumber(value: Double($0))
    }
    return SCNParticlePropertyController(animation: animation)
}

/// A soft radial-gradient sprite in steam gray — the particle color
/// does not reliably tint `particleImage`, so the gray is baked in.
private func smokePuff() -> NSImage {
    NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0.82, alpha: 0.9),
            NSColor(calibratedWhite: 0.68, alpha: 0.4),
            NSColor(calibratedWhite: 0.6, alpha: 0),
        ])
        gradient?.draw(in: rect, relativeCenterPosition: .zero)
        return true
    }
}

// MARK: - Headlight

/// The visible beam: a warm additive cone reaching forward (-x) from
/// the lamp. SceneKit lights need geometry to land on and the lane is
/// transparent, so the cone itself is the "beam".
private func headlightBeam(scale s: CGFloat) -> SCNNode {
    let length = 150 * s
    let beam = SCNNode()
    beam.name = "headlight-beam"
    beam.geometry = SCNCone(
        topRadius: 20 * s, bottomRadius: 4 * s, height: length)
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = NSColor(
        calibratedRed: 1, green: 0.85, blue: 0.55, alpha: 1)
    material.transparency = 0.22
    material.blendMode = .add
    beam.geometry?.materials = [material]
    beam.eulerAngles.z = .pi / 2 // cone +y axis -> -x (forward)
    beam.position = SCNVector3(Float(-length / 2), 0, 0)
    return beam
}

/// Real illumination for whatever the beam crosses: a spot on the
/// lamp node aimed down the same -x axis (light travels along the
/// node's negative z, so yaw π/2).
private func headlightSpot() -> SCNNode {
    let node = SCNNode()
    node.name = "headlight-spot"
    node.eulerAngles.y = .pi / 2
    let light = SCNLight()
    light.type = .spot
    light.color = NSColor(calibratedRed: 1, green: 0.85, blue: 0.6, alpha: 1)
    light.intensity = 900
    light.spotInnerAngle = 18
    light.spotOuterAngle = 40
    light.attenuationEndDistance = 700
    node.light = light
    return node
}

/// The lamp itself glows: copy the shared brass trim material (the
/// domes and chimney share it) and add a warm emission to the copy.
private func lampGlow(_ headlight: SCNNode) {
    guard let original = headlight.geometry?.materials.first,
          let material = original.copy() as? SCNMaterial else { return }
    material.emission.contents = NSColor(
        calibratedRed: 1, green: 0.82, blue: 0.5, alpha: 1)
    material.emission.intensity = 1.2
    headlight.geometry?.materials = [material]
}

/// A faint warm emission inside the cab — same copy-the-shared-
/// material trick so the boiler keeps its plain paint.
private func cabGlow(_ cab: SCNNode) {
    guard let original = cab.geometry?.materials.first,
          let material = original.copy() as? SCNMaterial else { return }
    material.emission.contents = NSColor(
        calibratedRed: 1, green: 0.72, blue: 0.4, alpha: 1)
    material.emission.intensity = 0.4
    cab.geometry?.materials = [material]
}
