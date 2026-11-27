# DECISIONS

- [init] Stack: Swift 6.3.3 + SPM executable + AppKit `NSWindow` overlay
  - SceneKit behind a `Renderer` protocol — native, single ~1 MB binary,
  zero runtime services; rejected RealityKit (no camera controls, ECS
  ceremony), game engines (100× the binary), ObjC (no gain)
  (<https://developer.apple.com/documentation/appkit>,
  <https://developer.apple.com/documentation/scenekit>)
- [init] SceneKit despite deprecation at SDK 26: simplest disposable
  choice, fully functional on macOS 27.x; `Renderer` protocol seam keeps
  an ARView/MTKView swap a contained change
  (<https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes>)
- [init] Command Line Tools toolchain via
  `DEVELOPER_DIR=/Library/Developer/CommandLineTools`: Xcode license is
  unaccepted on this machine so `/usr/bin/swift` fails; CLT builds
  AppKit/SceneKit fine (verified 2026-11-25). XCTest and swift-testing
  are NOT in CLT (verified), so tests run as a custom check harness
  executable (`slChecks`) — rejected waiting on `sudo xcodebuild
  -license` because the loop cannot run sudo (queued as Q0)
- [init] Model: procedural SceneKit-primitive locomotive bundled +
  `--model <file.usdz|scn|dae>` swap — user's answer; rejected vendored
  CC0 as *default* (licensing/asset pipeline cost), kept as next horizon
  (candidates: Quaternius Train Pack, Kenney Train Kit, grab3d Steam
  Train — all CC0)
- [init] Visibility: public + MIT — user's answer; upstream `sl` is MIT
  too (<https://github.com/mtoyoda/sl>)
- [init] Distribution: `make install` + GitHub Releases + Homebrew tap
  `sl3d` in existing `GeneralD/homebrew-tap` installing binary `sl` with
  `conflicts_with "sl", "sapling"` — user's answer; core name `sl` is
  taken (<https://formulae.brew.sh/formula/sl>). Source-built binaries
  skip Gatekeeper (no quarantine xattr); notarization rejected for v1
- [init] Sound off by default, `-s` flag enables (CC0 sources only:
  Wikimedia Commons, BigSoundBank — freesound.org needs OAuth, rejected)
- [init] Train lane: bottom strip of screen, right-to-left like the
  original; `--all` traverses every display; default = screen with the
  frontmost window
- [init] macOS 13+ floor, arm64 primary — SceneKit/overlay APIs are
  ancient; universal2 deferred to horizon
- [init] Concurrent `sl` invocations allowed, capped ~5 windows — it is
  the joke; unbounded would be a self-DoS
- [init] Tests = custom `slChecks` executable (see above) + `scripts/shot`
  screenshot lane; names are spec sentences; coverage via
  `swift build --enable-code-coverage` + llvm-cov (both verified in CLT)
- [fleet] Xcode license accepted mid-run — XCTest/brew unblocked, but
  slChecks stays the primary lane (working, spec-sentence names, no
  migration cost); `DEVELOPER_DIR=CLT` remains the canonical toolchain
  pin so all five squads build identically
- [init] Bold additions authored by orchestrator: Dock hop + ghost
  steam — both ride the trajectory/particle systems the boring tier
  already builds (notch hop dropped: the lane is a bottom strip, the
  notch never intersects it)
- [task-11] RunSpec defaults: bare `sl` pulls 1 car (`cars = 1`); `-w` sets `speedFactor = 1.5`; `-h` is the help alias (undocumented in sl.1, which is off-limits); `parse` returns `Result` so `main.swift` got a mechanical unwrap — run-loop wiring untouched
- [task-13] `TrainPresenter` applies poses to the lane `NSView` today;
  the SceneKit `SCNNode` swap keeps the same `update(t:)` call (no
  SceneKit renderer exists yet — presenter stays view-agnostic)
- [task-26] -F fly: literal upstream port — `y = (laneWidth - x)/7 + trainHeight/2` in y-up lane points (slope exactly 1/7, nose-up tilt `-atan(1/7)`); the strip window is kept, so the train exits through the strip's top edge in the upper-left region rather than the screen corner. Tilt goes through `NSView.boundsRotation`: the backing layer's affine transform is reset by AppKit's layer-geometry sync and never renders
- [spike-b #3] SceneKit committed: `SCNView` composites a transparent
  background into the overlay on this stack — clear `backgroundColor`,
  non-opaque layer, and clear `scene.background.contents` are sufficient;
  the `wantsHDR` black-pixel trap did not fire (HDR props live on
  `SCNRenderer`, left at defaults). Evidence lives in
  `docs/spikes/b-scnview.md` and `docs/shots/spike-b-scenkit.png`;
  dev toggle `SL_RENDERER=scenkit`
- [task-34] Audio assets vendored at `share/sl/audio/` (not
  `Sources/sl/Resources/` — keeps Package.swift and SPM resource
  handling untouched); `make install` ships them to
  `$(PREFIX)/share/sl/audio/`; `AudioAssets` resolves argv0-relative
  (executable ancestor walk, then cwd ancestor walk for scratch/worktree
  builds)
- [27] `--all` lane: one global rect spanning all screens' x-extent at
  the lowest bottom edge; each per-screen window shows the train only
  when its global rect intersects that display's strip — staggered
  displays may legitimately skip the train (docs/fieldcheck.md)
- [task-19] `SceneKitRenderer` is the default renderer — transparent
  `SCNView` + ortho pixel-space camera + ambient/directional lights +
  placeholder primitive driven by `Trajectory`; `SL_RENDERER=placeholder`
  keeps the skeleton view for A/B debugging
- [task-12] `--duration` needed a RunSpec field + one parser case (flag
  table entry only — parser internals untouched); RunLoop caps the run
  at min(--duration ?? 10s, driver.duration), watchdog = cap + 30s
- [task-12] SIGINT contract: SIG_IGN unless -e, in which case main's
  slot-releasing handler stands and exits ~130; freeze holds via
  app.run() until SIGTERM; FrameDriver seam = duration +
  onFrame(t)->Bool + render(at:) with adapters in main.swift, and the
  audio-tail/fade-out finish sequence rides inside `OverlayDriver`'s
  onFrame so RunLoop stays traversal-agnostic
- [task-37] `-a` visual half: `ScreamerField` hangs dark `car-window`
  planes with two figure sprites each off the train node, placed from
  the train's content `boundingBox` so it survives pivot conventions
  (procedural loco track-contact vs centered `--model`); pop cycles are
  pure functions of `t` (golden-ratio phases, ~1.15 s period). Loco
  "rock" is a ±0.045 rad roll on `eulerAngles.x`. `RunSpec.wantScreams`
  is a computed `accident` passthrough — the audio engine reads it;
  `-s` still gates actual sound.

- [task-28] Dock hop: zone detected via `visibleFrame.minY - frame.minY` > 8 (bottom Dock only — a side Dock insets minX/maxX); the Dock's width is not public API, so the hop zone approximates it as a centered strip capped at 600pt; hop = 40px parabola + 0.15 rad pitch, skipped under `-F` flight; `--all` collects one zone per screen mapped into global lane coords
- [task-32] `-G` swaps the node builder (`ProceduralTGV`, bullet silhouette) rather than the `Livery` enum — silhouette, not paint; `-c` is the red-edged scheme: vermilion body, charcoal trim (was brass); `Livery.variant` stays reserved

- [25] Frame pacing: `RunLoop` drives `onFrame` from CVDisplayLink
  (vsync-locked, ProMotion-aware, no drift) via a Sendable trampoline
  that hops C callbacks to the main queue; Timer at
  `SLCore.FramePacing.fallbackInterval` (1/120 s) is the fallback.
  Chose the classic `CVDisplayLinkCreateWithActiveCGDisplays` +
  `SetOutputCallback` + `Start`/`Stop` API because the CLT SDK lacks
  the newer one-shot create, and CVDisplayLink over CADisplayLink
  because CADisplayLink needs a view/screen while overlays are
  borderless agents. The API is deprecated in the macOS 15 SDK
  (`NSView.displayLink` needs macOS 14; package targets macOS 13) —
  revisit when the deployment target moves. `OverlayDriver`'s fade
  now advances by real frame dt since the panel rate isn't fixed.
- [task-23] Cars ride inside the train node so pose/heading/wheelwork/disco reach them; a --model wrapper pre-scales local space so the chain counter-scales by 1/nodeScale; consist center shifts +x by chainLength/2 and Trajectory.trainWidth grows by chainLength so the last car exits before finished; car wheels reuse the wheel-* hook so WheelworkAnimator spins them
- [task-31] `-l` now scales the whole consist at 0.6 — including a `--model` loco (node scale multiplies the wrapper's normalization) and its car chain (`carScale = locoScale` unconditionally); `-d`'s scale pulse composes on a stored `baseScale` instead of clobbering node scale
- [task-71] The "3/4" camera is elevation-only (offset in the y-z plane, no yaw): any x-offset yaws the view and rotates the consist off the lane's horizontal, breaking the right-to-left read; `look(at:)` keeps the horizon level and `orthographicScale` stays height/2 since isotropic zoom would crop consist width
- [task-73] Lane strip is now `laneFraction` (0.6) of screen height; scene scale = lane/referenceLaneHeight (180) × `--scale` × `-l`. `--scale <f>` chosen over `--zoom` (matches "scale" wording of effects params). `--model` normalizes to the locomotive's design height instead of lane height so `locoScale` lands it at the procedural loco's size; ghost-steam y clamps and DockZone apex are lane-height fractions
- [task-75] `--model` + `-<n>` couples the bundled USDZ cars (tender first, then coaches) via `ModelConsist`: heights keep real-world proportion to the loco (each car normalized by `carRawH / locoRawH` against bundled `loco.usdz` as the meter reference — works for custom `--model` files too since the loco always normalizes to the same design height). Car length is capped at `maxCarLengthFactor` (1.5) loco lengths, squashed along x only — the express coach's real ~2:1 ratio would otherwise fill more than the whole lane; height keeps real proportion since only x compresses. Car bottoms align to the rail line via centered-pivot `position.y = height/2`; spacing reuses `Car.couplingGap` in design units; missing/unloadable assets fall back to procedural `Car.cars` (all-or-nothing, no partial consist). USDZ cars carry no `wheel-*`/`rod-*` node names, so `WheelworkAnimator` stays nil for `--model` — static cars, same as the loco. `shot-render` needed no fix: `SceneKitRenderer`'s defensive `spec.model` reload already resolves `--model` offscreen.
- [task-75] `Trajectory.pose` `finished` was a borderline float compare (`x + trainWidth/2 <= -margin` lands exactly on the boundary at p==1); arbitrary consist widths from real car lengths could land an ulp above and the run never reported finished — ghost steam/fade skipped. Now `p >= 1 ||` guards it; geometrically equivalent since `end` is constructed to put the right edge at `-margin`.
- [cars-flag] `--cars <n>` accepts 0-50: 0 runs the loco light (renderer already guards `carCount > 0`), 50 still outgrows the screen without absurd node counts; `-<n>` stays 1-10 for classic parity. `invalidCarCount` now carries an `expected` range string so each caller names its own bound.
- [task-78] The bundled `share/sl/models/loco.usdz` is now the default train; `ProceduralLocomotive`, `ProceduralTGV`, `Livery`, `Car` geometry, `WheelworkAnimator` and the `-c`/`-G` flags are deleted. `ModelAsset.locomotiveDesignHeight` (154) replaces the procedural loco's height as the normalization target and the bundled cars' proportion meter. `chimney`/`headlight` anchors are synthesized from the model bounding box (front = -x, cars couple +x) inside `anchorModelLocomotiveEffects`, which folds the wrapper's normalization scale into the anchor scale so effect-local units stay design units — it must run before `locoScale` multiplies the wrapper. `couplingGap` moved from `Car` into `ModelConsist`. Missing bundled assets are a usage error (exit 2) like a bad `--model`, preflighted for both loco and cars before the window opens.
- [crop-fix] ModelAsset.normalized baked the bbox-centering offset into the WRAPPER's `position` — but `SceneKitRenderer.render` writes the trajectory pose into that same position every frame, silently discarding the centering: models rendered bottom-at-center-y, half a train too high, tops cropped out of the lane. Centering now lives on an inner `model-content` node; the wrapper keeps only scale, so pose writes are safe. Same stomp applied to car nodes (`ModelConsist.chain` sets `position` directly) — fixed for cars too.
- [fix/cars-smoke] The car-chain anchor divided design units by `nodeScale` (normalization × `locoScale`), but design→wrapper-local needs the normalization scale alone — at `--scale`≠1 or `-l` the anchor shrank by `locoScale`, tucking the chain toward the loco center and floating the tender off the rail. Divided by `norm = nodeScale/locoScale`; regression check builds the view at laneHeight 360 (locoScale 2) and asserts the anchor lands at the loco rear-bottom in scene units. Chimney smoke is disabled on the model: the `size.height * 0.70` fraction assumed a bottom pivot but the model's pivot is centered (bbox top = 0.5·h), so puffs spawned 0.2·h in mid-air. `anchorModelLocomotiveEffects` no longer synthesizes `chimney`; the smoke emitter + `attachLocomotiveEffects` stay in code for re-enable once a correct anchor exists (smokebox position can't be derived from a bare bounding box — needs a named mesh or a hand-tuned offset for the bundled asset). Ghost steam falls back to the train origin, so the post-exit fog still drops.
- [wheelwork] `ModelWheelwork` re-rigs the bundled loco: `driver_*`/`wheelset_*` spin about local +x (the axle axis ↔ world lateral) at angle = accumulated scene distance / per-wheel world radius — `-w`/`--scale`/`-l`/dock-hop compose for free and a paused pose stops the wheels. Coupling rods orbit at the measured crank radius (|rod pivot − driver_2 axle| = 0.33, rest angles −45°/−135° so the sides stay quartered) with rigid circular translation — they never rotate. Crossheads slide longitudinally on the crank's x projection; connecting rods aim crosshead-pin → crank-pin in the y-z plane each frame. Valve gear (`eccentric_rod`, `expansion_link`, `radius_rod`, `combination_lever`, `union_link`) stays static — small parts, revisit if the gap reads. `SCNNode.rotation` is axis-angle, not a quaternion: first pass wrote `(sin θ/2, …, cos θ/2)` and the rod swung ~57° skyward; the regression check asserts rod tilt < 0.3 rad and a constant crank radius so the trap is pinned.
- [wheelwork-sign] Wheel roll is a NEGATIVE local-x rotation: local +x maps to world -z (rod pivots at local x ±0.93 sit at world z ∓0.93), and a left-rolling wheel needs world +z positive. First pass shipped +angle — visibly reversed (user-reported). The crank orbit math was already world-based so rods stayed correct; only the wheel sign flipped.
- [ghost-gate] Ghost steam now requires a `smoke` anchor: it is the last chimney puffs lingering, so with chimney smoke disabled on the bundled model it spawned unexplained fog at the lane's left edge after exit (user-reported). `dropGhostSteam` drops only when a `smoke` node exists, and `postExitHold`/`postExitRemaining` return 0 without one — the fade starts at exit instead of holding an empty lane for 1s. Checks inject a bare `smoke` node to keep exercising the emitter path; re-anchoring the chimney revives the feature automatically.
- [model-facing] The bundled assets are authored facing +x (smokebox/cylinders toward the cars): the loco ran cab-first, the tender coupled to its FRONT buffer beam, and the `-x`-computed headlight anchor landed on the rear — the "weird light" the user reported. `ModelAsset.normalized` now yaws `model-content` π so loaded models face -x; the anchor math, consist anchor (+x = rear) and headlight aim all become correct for free, and the same flip straightens the cars. Wheelwork sign map flips with it (local y→world +x, local x→world +z): wheel roll is a POSITIVE local-x rotation again, rod/crosshead longitudinal offsets are +dc, and `restAngle` is atan2(dz, dy) — superseding [wheelwork-sign]. Custom `--model` files inherit the same authored-facing-+x contract. Regression pin: crosshead (cylinder = front) must sit world -x of `driver_2`.
- [beam-fade] The headlight cone rendered as an opaque yellow wedge: `blendMode = .add` ignores alpha entirely, so `transparency` never applied (procedural era hid it under a small scale). Now alpha-blended with a lengthwise gradient texture (dense at the lamp, zero at the far end) + `writesToDepthBuffer = false`, and the cone slimmed (140×12 units) so it reads as a light shaft, not a solid mass.
- [smoke-back] Chimney smoke re-enabled on the bundled model now that the model faces -x (post-[model-facing]): a `chimney` anchor at (-w/2+0.17w, 0.46h-19) lands the emitter under the rim — measured against the rendered frame. The +19 rise is the emitter's own offset (chimney node convention from the procedural era), so the anchor sits rim-minus-offset. `isLocal=false` particles already linger in world space (the trail stays where the chimney passed) and the opacity keyframe fades oldest-first — the requested behavior needed no new particle work. Ghost steam revives automatically through its smoke-anchor gate, so the post-exit trail has a real source again. Checks flip: rendered loco must carry `smoke`; the ghost-gate check strips the real anchor instead of injecting a fake one.
- [camera-angle] `--angle <deg>` adds a camera azimuth to the 3/4 ortho view: the horizontal reach (1200pt, elevation ~37deg) rotates toward -x so the loco runs diagonally down-left with its smokebox face visible (sketch brief: diagonal rails, train approaching lower-left). Default 25deg; `--angle 0` restores the flat side-on lane of [task-71], and 0-75 is the accepted range. Only the camera pose changes — trajectory, heading and wheelwork are untouched since ortho azimuth needs no world-space motion. Reversible with one flag unlike baking a yaw into the model or the path.
- [angle-fit] `--angle`'s diagonal drift (stripWidth × cameraTiltSlope 0.6 × tan(az)) exceeds the strip's free height — the consist's top cropped at the window's upper edge on entry (user-reported). The window now grows upward by the drift via `OverlayGeometry.viewHeight`, capped at the screen's own height; `orthographicScale = frame.height/2` keeps the 1:1 world↔point mapping so the extra room is just more world, not a zoom-out. `addCamera` now aims at the *lane* centre (`laneHeight/2`, not frame centre) so the diagonal's midpoint lands mid-window and the residual clip — `(drift + trainH) − viewHeight`, only when the screen cap bites — splits symmetrically top-right vs bottom-left, the provable minimum. `shot-render` shares the same `viewHeight` so evidence matches live. `--all` is untouched (glyph stage, no SceneKit camera).
- [angle-perspective] `--angle` > 0 now uses a *perspective* camera — ortho has no foreshortening so the diagonal read as a flat slide, not the sketched approach (user-reported: "no depth"). `fieldOfView = 2·atan(scale/1500)` keeps the target-plane framing identical to the ortho scale, so mid-lane size is unchanged while the far right end shrinks into the distance and the near left end grows past the camera. Perspective `zNear` must be positive (1/10000); ortho keeps -5000/5000. `--angle 0` stays fully ortho — the classic lane. Camera checks pin both branches: default asserts !ortho + fov≈ortho match, `--angle 0` asserts ortho + scale 90.
- [ghost-out] Ghost steam removed entirely (supersedes [ghost-gate], partially [smoke-back]): the after-exit fog read as a smoke clump materializing at screen-left once the consist cleared (user-reported) — even with a real chimney source it was a second emitter's worth of fog, not lingering puffs. The whole seam went: `ghostSteamEmitter`/`ghostSteam`, `dropGhostSteam`/`stopGhostEmission`, `exitedAt`, `ghostSteamDuration`/`ghostEmitWindow`, and the `postExitHold`/`postExitRemaining` members they were the only consumer of — `Renderer`, `FrameDriver` and both `main.swift` adapters drop the members rather than keep a defaulted-0 surface nobody uses. The finish fade now waits only on `running || whistle tail`; the chimney smoke's own world-space puffs still linger and fade on the trajectory they were emitted along — the trail the user actually asked for. `GhostSteamChecks` deleted wholesale; the consist-exit and scale checks lose their ghost clauses.
- [angle-40] Default `--angle` raised 25 → 40 (supersedes the default in [camera-angle]): at 25° the consist still read as sliding sideways; at 40° the near end fills the frame as it passes — the "approaching out of the distance" composition the user asked for. Shot-rendered 35/45/60: 45 already crops the near end hard, 35–45 is the sweet spot, 40 sits mid-range. Geometry and checks re-pinned (camera yaw/z-reach, parse default); `--angle 0` and the 0–75 range are unchanged.
- [puff-round] Smoke puffs rendered as faint squares: `smokePuff` drew the radial gradient with `draw(in: rect)`, which runs the gradient out to the rect's corners — the edge midpoints never reach α=0 so every sprite kept a visible quad outline (user-reported: "smoke looks square"). Now drawn into the inscribed `NSBezierPath(ovalIn:)` — the gradient ends at the circle's rim, corners stay untouched, puffs are round. Verified on the live screen: the trail is a string of round blobs.
- [trackside-cam] The angled camera drops from the overhead crane to a low trackside position (supersedes the angled geometry in [angle-40]): reach 1200→1000, height 900→350, so distance 1500→1059 and elevation ~37°→~19° — the rail-fan vantage where the consist looms over the viewer. Default azimuth 40→55 brings the approach more head-on; the far:near distance ratio at the lane ends goes ~1.7→~2.8, the depth differential the "no perspective" complaint was after. `cameraTiltSlope` tracks the new elevation (0.6→0.33); `viewHeight` math unchanged. The flat `--angle 0` ortho lane keeps the old 1200/900 reach — classic framing untouched. Fov formula now uses the real camera distance instead of a literal 1500.
- [livery] `--color <name|deg>` resprays the consist. Two material paths: saturated `NSColor` diffuses (s≥0.2, b≥0.15) get absolute hue overrides with a 0.68 saturation floor so muted paint reads as paint — neutrals (coal, metals, glazing) keep their finish; textured materials get a `CIColorMonochrome` wash so the whole atlas takes the hue while luminance shading (weathering, lining) survives. USDZ texture contents arrive as `NSURL` with `?offset=&size=` byte-range queries — sliced out of the memory-mapped archive since `CIImage(contentsOf:)` can't open them; plain files, CGImage and NSImage contents also handled. Rejected approaches documented for the next person: CIAreaAverage dominant-hue → `CIHueAdjust` landed olive (trim drags the mean); a saturation-weighted 12-bin histogram fixed the estimate but the rotate still washed muted green paint into dusty hues and amplified baked weathering into blotches; `CIBlendWithMask` at 0.78 delivered only ~30% effect (mask luminance semantics). `black`/`gray` pull saturation+brightness for a neutral monotone finish; names plus 0-359 degrees parse in `RunSpec.Livery`. Applied once at `makeView` after `locoMaterials` collects — `-d`'s per-frame strobe simply overrides the colours while it runs.
- [livery-two-tone] `black` is now a two-tone livery: matte-black body + gold accents. `Livery.Accent` (hue/sat/bri + `hueRange` 0...0.17) repaints saturated materials whose own hue falls in the orange family — brass/copper/fire fittings go gold instead of monotone black. `Livery.matte` kills specular (`specular` → 0.04 gray, `shininess` → 0.1) on every resprayed surface EXCEPT accents — polished-metal gold on dead-black paint is the contrast that makes it read. `resprayColor` now returns a `Repaint` (.none/.body/.accent) so applyLivery can matte body+texture but leave accents shiny. Atlas lining keeps its luminance shading under the black wash — the thin gold lining on the boiler survives as subtle detail. (user-requested "matte black with gold accents")
- [smoke-billow] Chimney smoke retuned for a rolling billow (user-reported "smoke should bloom wider"): birth 14→18/s, life 2.6→3.6s, velocity 18→15 (slower rise stays denser), spread 28°→42°, damping 0.5→0.35, size 8→12±4pt, growth curve 0.6→2.6× to 0.5→3.4×, plus a gentle upward `acceleration` (0,4,0) for buoyant climb. Puffs now bloom into a fat rolling cloud above the stack instead of a thin jet. Peak opacity stays ≤0.55 so the lane never opaques over.
- [camera-loom] Trackside camera pulled closer+lower (supersedes the position in [trackside-cam]): reach 1000→840, height 350→170 — distance 1059→857, elevation ~19°→~20° from the railhead, near-end pass ~580→~510pt off the lens. far:near ratio ~2.6; the consist now fills the frame as it passes — the "charging at you" loom the user asked for. Fov/compensation math unchanged (`2·atan(scale/dist)` with real dist); `--angle 0` ortho lane untouched.
- [launch-fade] Launch flash fix (user-reported "screen flashes when sl appears"): the window ordered in BEFORE SceneKit's first drawable committed, so the unpainted Metal frame could flash opaque for a beat. Windows now `orderFrontRegardless` at `alphaValue = 0`; `OverlayDriver` ramps all windows 0→1 over `Hardening.fadeInDuration` (0.25 s) using the same real-dt machinery as the fade-out — the ramp finishes while the consist is still off-screen, invisible to the user. `--freeze` can't take the ramp (no `onFrame` ticks), so `OverlayDriver.render(at:)` reveals alpha 1 directly after the frozen frame paints.
- [matte-lighting] Matte liveries stage their own lighting (user-requested dimensionality on matte black): a directional rim light behind and above the lane (`rim-light`, (500,420,-420)→lane centre, intensity 750, cool white) rakes the crown and far-flank edges so the silhouette separates from the dark body; `scene.lightingEnvironment` gets a 3-stop studio-softbox gradient (bright sky over dark ground) at intensity 0.65 for an image-based sheen sweep along the flanks. `mattify` drops specular to a broad 0.10 whisper (not zero — matte paint still reflects the sky, spread wide) plus `metalness` 0.35 so the environment actually reads; accent fittings keep their factory specular as polished metal. Scoped to `livery.matte` so colour liveries keep the plain two-light rig.
- [smoke-lift] Smoke must read AT the stack (user-reported lag): the fade controller ran on default even keyTimes, so opacity peaked at 33% of the 3.6s life — puffs stayed translucent ~1.2s while the train moved a full length past them, and birth size 0.5x12pt was a speck. Explicit keyTimes now: opacity near-peak by 8% of life ([0,0.55,0.62,0.5,0] @ [0,0.08,0.25,0.7,1]), size born at 1.0x14pt then fast early bloom ([1,1.5,2.5,3.4] @ [0,0.15,0.6,1]). Velocity 15->22 + spread 42->30 tightens the throat so the column "stands up" then loosens; birthRate 18->30 keeps the plume dense at the new speed. Note: `SCNView.snapshot()` does not advance particle time — offscreen shot-render shows only the ~150ms wall-clock birth window, so smoke density can only be verified on a live run.
- [default-livery] Default livery is now `black` (matte black + gold fittings + staged lighting) — the signature look should not need `--color` (user asked why the default wasn't black). `--color factory` or `--color none` restores the as-built finish; every other name/degree still resprays. Checks pin the default on `spec(["sl"])` itself and the factory opt-out on both names.
- [smoke-born-visible] Smoke fades while it rises, not after a lid: opacity curve now starts at 0.62 and declines over life ([0.62,0.55,0.3,0] @ [0,0.3,0.7,1]) — clear the instant it leaves the stack, thinning as it climbs, instead of hold-then-fade (which read as a persistent layer).
- [smoke-spread] Plume widens more on the climb (user asked for more spread): spread 30->40 degrees at birth, velocity variation 8->10 for scatter, and the grow curve's tail keeps swelling to 4.1x (was 3.4) so puffs bloom wide as they thin — the column fans out instead of staying a narrow rope.
