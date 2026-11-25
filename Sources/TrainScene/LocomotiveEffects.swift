import AppKit
import QuartzCore
import SceneKit

/// Atmosphere layered onto the locomotive: chimney smoke (an
/// `SCNParticleSystem` of soft puffs that drift, grow and fade), the
/// headlight's emissive beam cone + spot light, and a faint warm
/// emission inside the cab. Everything is looked up by node name —
/// the procedural loco shipped `chimney`/`headlight`/`cab` nodes, and
/// `anchorModelLocomotiveEffects` synthesizes the first two for a
/// loaded model, which carries neither. `scale` is the effect-size
/// factor; for model runs it is 1 because the anchors convert their
/// local space to design units and the ancestors apply `locoScale`.
@MainActor
public func attachLocomotiveEffects(to loco: SCNNode, scale: CGFloat = 1) {
    if let chimney = loco.childNode(withName: "chimney", recursively: true) {
        chimney.addChildNode(smokeEmitter(scale: scale))
    }
    if let headlight = loco.childNode(withName: "headlight", recursively: true) {
        lampGlow(headlight)
        headlight.addChildNode(headlightBeam(scale: scale))
        headlight.addChildNode(headlightSpot(scale: scale))
    }
    if let cab = loco.childNode(withName: "cab", recursively: true) {
        cabGlow(cab)
    }
}

// MARK: - Model anchors

/// A loaded model (`model-loco` wrapper) carries no `chimney` or
/// `headlight` node names, so `attachLocomotiveEffects` would find
/// nothing. This synthesizes plain anchor nodes from the model's
/// bounding box — chimney near the front-top, headlight on the front
/// face's upper area (front of travel is -x; cars couple +x) — as
/// children of the wrapper, then the caller attaches the shared
/// effects.
///
/// `size` is `ModelAsset.Loaded.size` (design units, centered pivot).
/// Each anchor's own scale folds the wrapper's normalization scale
/// back out, so anchor-local units ARE design units: effect sizes
/// inside them ride `locoScale` through the ancestors exactly like
/// the procedural loco's baked scale did — call
/// `attachLocomotiveEffects(to:scale:)` with `scale: 1` afterwards.
/// MUST run before the wrapper's scale is multiplied by `locoScale`,
/// while `loco.scale`/`loco.position` still hold the normalization
/// transform `ModelAsset` authored.
@MainActor
public func anchorModelLocomotiveEffects(on loco: SCNNode, size: CGSize) {
    let s = loco.scale
    func anchor(_ name: String, _ x: CGFloat, _ y: CGFloat) {
        let node = SCNNode()
        node.name = name
        node.scale = SCNVector3(1 / s.x, 1 / s.y, 1 / s.z)
        // Design point -> wrapper-local: undo position, divide by the
        // normalization scale (uniform in practice, per-axis safe).
        node.position = SCNVector3(
            Float((x - CGFloat(loco.position.x)) / s.x),
            Float((y - CGFloat(loco.position.y)) / s.y),
            Float((0 - CGFloat(loco.position.z)) / s.z))
        loco.addChildNode(node)
    }
    // Fractions of the bounding box, not absolutes: the bundled loco
    // is ~2.2 design-units wide per unit of height, so x fractions of
    // `size.width` land the chimney on the smokebox crown and the
    // lamp on the nose face. (Logged in DECISIONS.md.)
    anchor("chimney", -size.width * 0.25, size.height * 0.70)
    anchor("headlight", -size.width / 2 + size.width * 0.02,
           size.height * 0.18)
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

/// Ghost steam: the after-image the lane keeps for ~1s after the
/// consist clears the left edge. A broad emitter dropped where the
/// train was — world-space (`isLocal = false`) puffs that rise, drift
/// back along the lane and fade on their own. `scale` is the `-l`
/// factor like the chimney smoke.
public func ghostSteamEmitter(scale: CGFloat = 1) -> SCNNode {
    let node = SCNNode()
    node.name = "ghost-steam"

    // A wide, flat shell: birthLocation .surface spreads puffs along
    // the strip, so the fog reads as a trail over the lane's left
    // end rather than a single puff.
    let shell = SCNBox(
        width: 240 * scale, height: 24 * scale, length: 2,
        chamferRadius: 0)
    let shellMaterial = SCNMaterial()
    shellMaterial.lightingModel = .constant
    shellMaterial.diffuse.contents = NSColor.clear
    shellMaterial.transparency = 0
    shell.materials = [shellMaterial]
    node.geometry = shell

    node.addParticleSystem(ghostSteam(scale: scale))
    return node
}

/// Fog-trail tuning on the chimney smoke's skeleton: slower, larger,
/// shorter-lived puffs so the whole trail decays inside the ~1s
/// post-exit hold. `warmupDuration` pre-ages puffs so a `--freeze`
/// shot at exit+0.5s still shows a developed trail.
private func ghostSteam(scale s: CGFloat) -> SCNParticleSystem {
    let steam = SCNParticleSystem()
    steam.birthRate = 80
    steam.emissionDuration = 1
    steam.warmupDuration = 0.9
    steam.particleLifeSpan = 1.2
    steam.particleLifeSpanVariation = 0.3
    steam.particleVelocity = 9
    steam.particleVelocityVariation = 5
    steam.emittingDirection = SCNVector3(0.5, 1, 0)
    steam.spreadingAngle = 40
    steam.dampingFactor = 0.6
    steam.particleColor = NSColor(calibratedWhite: 0.78, alpha: 1)
    steam.particleColorVariation = SCNVector4(0.05, 0.05, 0.05, 0.1)
    steam.particleSize = 16 * s
    steam.particleSizeVariation = 6 * s
    steam.particleImage = smokePuff()
    steam.blendMode = .alpha
    steam.sortingMode = .distance
    steam.isLightingEnabled = false
    steam.isLocal = false
    steam.isAffectedByGravity = false
    steam.propertyControllers = [
        .opacity: fadeController(),
        .size: growController(),
    ]
    return steam
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
/// node's negative z, so yaw π/2). `scale` stretches the attenuation
/// reach with the beam so the pool still lands ahead of the nose.
private func headlightSpot(scale s: CGFloat) -> SCNNode {
    let node = SCNNode()
    node.name = "headlight-spot"
    node.eulerAngles.y = .pi / 2
    let light = SCNLight()
    light.type = .spot
    light.color = NSColor(calibratedRed: 1, green: 0.85, blue: 0.6, alpha: 1)
    light.intensity = 900
    light.spotInnerAngle = 18
    light.spotOuterAngle = 40
    light.attenuationEndDistance = 700 * s
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
