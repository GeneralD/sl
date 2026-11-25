# ADR: scene stack — SceneKit behind a `Renderer` protocol

## Status

Accepted (Phase 0). Revisit only if the transparency spike (spike B)
proves `SCNView` cannot composite a transparent background.

## Decision

SceneKit `SCNView` inside the overlay window, behind the `Renderer`
protocol (`Sources/TrainScene/Renderer.swift`), adopting the verified
`peterhanily/max_clawdroom` (Apache-2.0) recipe:

- Transparent compositing: `scnView.backgroundColor = .clear` +
  `scene.background.contents = NSColor.clear`; the window itself is
  non-opaque.
- **HDR trap (spec quirk, verbatim from the exemplar):** do NOT enable
  `wantsHDR` / `wantsExposureAdaptation` — exposure computation treats
  clear pixels as black and turns the whole strip dark.
- Orthographic camera in a 3/4 overhead pose (`usesOrthographicProjection`,
  `orthographicScale = height/2` unchanged): the camera sits ~37° up in
  the y-z plane — elevated and toward the viewer, no yaw, so the
  consist stays level on the lane — and looks at lane center, so
  boiler crowns, domes, the cab roof and wheel/rod depth read while
  the train still crosses right-to-left. Scene units are lane points,
  no longer 1:1 screen points.
- Traversal: `SCNAction.sequence([.moveTo(...), .run { exit }])` with
  `.linear` timing — the `.run` block posts the finish signal.
- `-F` flight maps to the original `sl.c`'s diagonal climb (`y = x/7`).
- Wheels/rods: `.repeatForever` rotation on wheel nodes; smoke is a
  SceneKit particle system.
- Model: procedural primitives default; `--model` loads
  `.usdz`/`.scn`/`.dae` via `SCNScene(url:)` (never bare `MDLAsset`
  without `loadTextures()` — renders white).

## Consequences

- SceneKit is deprecated since the 26 SDK (maintenance mode): the
  `Renderer` seam caps a future ARView/MTKView swap to TrainScene.
- glTF/GLB is NOT loadable — `--model` documents USDZ/SCN/DAE only.

## Rejected

- RealityKit ARView (sanctioned successor, but ECS ceremony + no camera
  controls for a non-AR use), raw Metal (write-your-own renderer),
  SpriteKit (2D), prerendered video (not a "3D model" per the brief).
