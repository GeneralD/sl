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
- [task-73] Lane strip is now `laneFraction` (0.6) of screen height; scene scale = lane/referenceLaneHeight (180) × `--scale` × `-l`. `--scale <f>` chosen over `--zoom` (matches "scale" wording of effects params). `--model` normalizes to the locomotive's design height (150) instead of lane height so `locoScale` lands it at the procedural loco's size; ghost-steam y clamps and DockZone apex are lane-height fractions
