# Spike B — SCNView transparent compositing

**Question:** can `SCNView` render a scene onto the transparent borderless
overlay with a see-through background (placeholder renderer already proved
the window layer — spike A verified)? The whole TrainScene module hinges
on it.

**Tried:** `Sources/TrainScene/SceneKitRenderer.swift` — `SCNView` with
`backgroundColor = .clear`, `wantsLayer` + non-opaque layer, clear
`scene.background.contents`, orthographic camera (scene units == screen
points), one lit spinning `SCNBox` sliding right-to-left through the lane
rect. Selected via `SL_RENDERER=scenkit` (`RendererFactory` in
`Sources/TrainScene/RendererFactory.swift`); placeholder stays the
default. HDR/exposure adaptation left at defaults (off) per the
`peterhanily/max_clawdroom` recipe — `wantsHDR`/`wantsExposureAdaptation`
live on `SCNRenderer`, not `SCNView`, and are not needed.

**Result:** WORKS — verified on this machine, 2026-11-26
(`docs/shots/spike-b-scenkit.png`, captured by
`SL_RENDERER=scenkit scripts/shot docs/shots/spike-b-scenkit.png`): the
orange box renders inside the bottom lane while every surrounding pixel
of the strip shows live desktop content — no black or opaque rect. The
premultiplied-alpha trap did not fire on this SDK/toolchain.

**Decisions confirmed:**

- **SceneKit is committed** as the TrainScene renderer; the `Renderer`
  protocol seam stays for the MTKView/ARView escape hatch.
- `SCNView` needs no special alpha plumbing beyond clear
  background + non-opaque layer on this stack.
- `SL_RENDERER=scenkit` remains as a dev toggle; the default run is
  unchanged until the real locomotive lands.

**Open follow-ups (moved to tasks):**

- Real locomotive scene graph (wheels, rods, smoke) behind the same
  `SceneKitRenderer` shape.
- `rendersContinuously = true` is spike-grade; the real renderer should
  render on demand (SCNView already redraws on scene-graph changes).
