# sl — a 3D steam locomotive that runs across your desktop

## Brief (verbatim)

SLコマンドを作りたいが3DモデルのSLがデスクトップの上を走るヤバいSLコマンドを作りたい。macOSに対応していればいい

## Vision (one line)

The classic `sl` typo gag escapes the terminal: a real-time 3D steam
locomotive drives across the actual desktop — over every open window, on
every Space — then is gone.

## Boring tier

### CLI contract (parity with mtoyoda/sl)

- Binary installed as `sl`, zero positional args.
- Flag parity re-imagined in 3D: `-a` (screaming passengers), `-c` (C51
  instead of D51), `-d` (disco strobe), `-e` (Ctrl+C allowed), `-F`
  (flies away, Galaxy-Express style), `-G` (French TGV livery), `-l`
  (little train), `-w` (windy/faster), `-<n>` (n trailing cars), `-v`
  (version); plus `-h`/`--help` usage table.
- Unknown flag → usage on stderr, nonzero exit. Clean run → exit 0.
- SIGINT ignored by default during the run (the punishment mechanic);
  `-e` restores it.
- Silent stdout; errors on stderr.
- `sl.1` man page installed, incl. the joke BUGS section
  ("It sometimes lists directory contents"), `SEE ALSO ls(1)`.

### Overlay window

- Borderless transparent non-opaque `NSWindow`, `hasShadow = false`.
- `level = .screenSaver`; `collectionBehavior` includes
  `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary` — visible
  over normal windows, the Dock, menu bar, and fullscreen-app Spaces.
- `ignoresMouseEvents = true` — fully click-through.
- `.accessory` activation policy — no Dock icon, no ⌘Tab entry, no focus
  steal, no menu bar.
- Zero permission prompts (no Accessibility, no Screen Recording, no
  notifications).
- Multi-monitor: default screen = the one with the frontmost window;
  `--all` traverses every connected display.
- Retina/ProMotion-correct frame pacing (display callback, no sleeps).
- Bounded lifecycle: process opens window, runs ≤ ~15 s, closes window,
  exits. Hard watchdog exit at duration + 30 s.

### 3D presentation

- Live render, not a sprite: SceneKit `SCNView` with transparent
  background (behind a `Renderer` protocol seam; MTKView swap stays a
  contained change).
- Animated, not gliding: spinning wheels + drive rods, smoke puffs,
  headlight, visibly coupled cars.
- Camera angle sells the 3D (slight perspective tilt).
- Trajectory: fully off-screen in → cross → fully off-screen out;
  bottom-of-screen lane, right-to-left like the original.
- Procedural locomotive built from SceneKit primitives as the bundled
  default; `--model <file>` loads a user-supplied `.usdz`/`.scn`/`.dae`.
- Sound off by default; `-s` enables chuff + whistle (CC0 audio only);
  `-a` implies cries.

### Process & lifecycle

- Runs from Terminal/iTerm/tmux as a bare CLI; spawns `NSApplication`
  itself, no `.app` bundle required.
- Headless/SSH → clear stderr message + nonzero exit, never a hang.
- Concurrent invocations allowed (independent trains), capped ~5
  windows.
- No residue: `pgrep -x sl` empty afterwards; no daemons, no launchd,
  no writes outside temp.
- No network, no telemetry, no config file for v1.

### Repo engineering

- `swift build` via Command Line Tools (`DEVELOPER_DIR`) — no Xcode GUI
  step, no `xcodebuild`, no XCTest dependency.
- arm64 primary; deployment floor macOS 13+.
- MIT license; upstream credit to Toyoda Masashi.
- README: install, flag table, screen recording of the gag.
- CI: build + headless checks + binary smoke test; release workflow
  tagging tarballs.
- Versioning + CHANGELOG.
- `make install` to `$(PREFIX)/bin` (`/opt/homebrew` default) + man page.
- Homebrew tap formula `sl3d` in `GeneralD/homebrew-tap`, installing
  binary `sl`, with `conflicts_with "sl", "sapling"` documented.
- GitHub Releases source tarball.

## Differentiator

Classic `sl` punishes the `ls` typo inside the terminal; this one
punishes it across the **entire desktop** — a real 3D locomotive over
every open window, on every Space.

1. Transparent always-on-top overlay hosting a live-rendered 3D train —
   the "ヤバい" payload; nobody expects their typo to leave the terminal.
2. Full `sl` flag parity re-imagined in 3D — `-F` actually flies,
   `-<n>` couples real wagons, `-a` screams, SIGINT-block enforced.
3. The command really is named `sl` and sits in PATH — the prank fires
   on the typo itself.

## Bold additions

- **Notch hop** — the train detects the camera notch on its lane and
  launches over it instead of clipping through → provisional: do
- **Ghost steam** — smoke particles linger and drift for a second after
  the train exits, leaving a translucent fog trail over the windows it
  crossed → provisional: do

## Next horizon

- `--ascii` headless fallback (classic terminal sl when no GUI session).
- Vendored CC0 model packs (Quaternius/Kenney/grab3d) selectable via
  `--model`.
- Sound default-on with volume control; doppler whistle panning.
- `~/.config/sl/` config file for default flags.
- Persistent desktop-pet mode (locomotive lives on the desktop).
- Random-ambush mode: train crosses at random intervals.
- Notch/weather/night variants; headlight beam in the dark.
- `.dmg` release + notarized binary; universal2/Intel.
- Companion gags (`sls`, `gti`).

## Done criteria

1. `sl` in Terminal → within ~1 s a 3D locomotive animates across the
   desktop over all open windows, exits, process terminates, exit 0.
2. Mid-run screen capture shows the train composited over a third-party
   window.
3. Run while a fullscreen app is on another Space → train visible there.
4. Ctrl+C mid-run does not stop the train; `sl -e` + Ctrl+C aborts.
5. A click mid-run hits the app beneath the train (click-through).
6. No Dock icon, no ⌘Tab entry, no focus steal during the run.
7. `sl -F` flies off upward; `sl -4` shows loco + 4 cars; `sl -l`
   miniature; `sl -c` different locomotive; `sl -w` visibly faster.
8. `sl --bogus` → usage + nonzero; `sl -v` prints version; `man sl`
   renders incl. BUGS joke.
9. Two rapid invocations → two trains; both exit; `pgrep -x sl` empty.
10. Headless invocation → stderr + nonzero, no hang.
11. `brew install generald/tap/sl3d` on a clean arm64 Mac installs a
    working `sl` — no Gatekeeper block, no permission prompts.
12. Screen recording shows moving parts (wheel rotation, smoke) — not a
    sliding static model.
