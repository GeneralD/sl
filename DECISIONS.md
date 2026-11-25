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
- [task-13] `TrainPresenter` applies poses to the lane `NSView` today;
  the SceneKit `SCNNode` swap keeps the same `update(t:)` call (no
  SceneKit renderer exists yet — presenter stays view-agnostic)
- [spike-b #3] SceneKit committed: `SCNView` composites a transparent
  background into the overlay on this stack — clear `backgroundColor`,
  non-opaque layer, and clear `scene.background.contents` are sufficient;
  the `wantsHDR` black-pixel trap did not fire (HDR props live on
  `SCNRenderer`, left at defaults). Evidence lives in
  `docs/spikes/b-scnview.md` and `docs/shots/spike-b-scenkit.png`;
  dev toggle `SL_RENDERER=scenkit`
- [task-19] `SceneKitRenderer` is the default renderer — transparent
  `SCNView` + ortho pixel-space camera + ambient/directional lights +
  placeholder primitive driven by `Trajectory`; `SL_RENDERER=placeholder`
  keeps the skeleton view for A/B debugging
