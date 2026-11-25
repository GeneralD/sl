import AppKit
import OverlayKit
import SLCore
import TrainScene

// sl — a 3D steam locomotive that runs across your desktop.
// main.swift: hardening gates, argv→spec dispatch, overlay windows and
// the frame driver; RunLoop owns the process contract from there.

/// Run-scoped UI state shared between the setup block and the frame
/// driver. `@MainActor` makes it `Sendable`, so the driver's `onFrame`
/// closure can capture it safely.
@MainActor
private final class RunUI {
    var windows: [OverlayWindow] = []
    var fade: Hardening.FadeOut?
}

/// The traversal-agnostic driver: wraps a `FrameDriver` base (the
/// single-display renderer or the --all stage) and owns the finish
/// sequence — audio tail, then fade-out — reporting "keep running"
/// through `onFrame` until the fade completes.
@MainActor
private final class OverlayDriver: FrameDriver {
    private let base: any FrameDriver
    private let audio: AudioEngine?
    private let ui: RunUI
    private var fading = false
    private var lastFrameT: TimeInterval?

    /// `duration` covers the post-exit hold and the fade too: the
    /// trail keeps the scene alive ~1s past exit and the fade needs
    /// its 0.2s on top before the run may close.
    var duration: TimeInterval {
        base.duration + base.postExitHold + Hardening.fadeOutDuration
    }

    init(base: any FrameDriver, audio: AudioEngine?, ui: RunUI) {
        self.base = base
        self.audio = audio
        self.ui = ui
    }

    var onFrame: (TimeInterval) -> Bool {
        { t in
            // Real frame delta: the display link fires at the panel's
            // own rate (60 or 120 Hz), so a fixed step would stretch or
            // compress the fade.
            let dt = self.lastFrameT.map { max(t - $0, 0) }
                ?? FramePacing.fallbackInterval
            self.lastFrameT = t
            if self.fading {
                guard var f = self.ui.fade else { return false }
                let alpha = f.advance(by: dt)
                for window in self.ui.windows { window.alphaValue = alpha }
                self.ui.fade = f
                return !f.isFinished
            }
            let running = self.base.onFrame(t)
            self.audio?.update(t: t, finished: !running)
            // Ghost steam: the scene holds after the consist clears
            // the lane so the smoke after-image dissipates; the fade
            // (finish) waits for the trail AND the whistle tail.
            let trail = self.base.postExitRemaining(at: t)
            let tail = self.audio?.tailRemaining(t: t) ?? 0
            guard running || trail > 0 || tail > 0 else {
                self.ui.fade = Hardening.FadeOut()
                self.fading = true
                return true
            }
            return true
        }
    }

    func render(at t: TimeInterval) {
        base.render(at: t)
    }

    var postExitHold: TimeInterval { base.postExitHold }

    func postExitRemaining(at t: TimeInterval) -> TimeInterval {
        base.postExitRemaining(at: t)
    }
}

/// Single-display adapter: the `Renderer` seam as a `FrameDriver`.
@MainActor
private struct RendererDriver: FrameDriver {
    let renderer: any Renderer

    var duration: TimeInterval { renderer.duration }

    var onFrame: (TimeInterval) -> Bool {
        { t in renderer.step(to: t) }
    }

    func render(at t: TimeInterval) {
        renderer.render(at: t)
    }

    var postExitHold: TimeInterval { renderer.postExitHold }

    func postExitRemaining(at t: TimeInterval) -> TimeInterval {
        renderer.postExitRemaining(at: t)
    }
}

/// `--all` adapter: the multi-screen stage as a `FrameDriver`.
@MainActor
private struct StageDriver: FrameDriver {
    let stage: MultiScreenTrain

    var duration: TimeInterval { stage.duration }

    var onFrame: (TimeInterval) -> Bool {
        { t in
            stage.update(t: t)
            return !stage.finished
        }
    }

    func render(at t: TimeInterval) {
        stage.update(t: t)
    }
}

let spec: RunSpec
switch RunSpec.parse(ProcessInfo.processInfo.arguments) {
case .success(let parsed):
    spec = parsed
case .failure(let error):
    FileHandle.standardError.write(Data("sl: \(error.message)\n".utf8))
    FileHandle.standardError.write(Data(RunSpec.usage().utf8))
    exit(2)
}

if spec.versionRequested {
    print(SLVersion.current)
    exit(0)
}

if spec.helpRequested {
    print(RunSpec.usage())
    exit(0)
}

// --- Hardening gates ----------------------------------------------------
// Headless first (no slot consumed), then the concurrency slot. The
// slot is held for the whole run and released on every exit path —
// normal exit via atexit, SIGTERM/SIGINT via the signal handler. The
// SIGINT handler doubles as the `-e` contract: RunLoop ignores SIGINT
// unless `-e` was passed, in which case this handler releases the slot
// and exits ~130.
if let reason = Hardening.liveHeadlessRefusal() {
    FileHandle.standardError.write(Data("sl: \(reason)\n".utf8))
    exit(1)
}

var activeSlot: Hardening.TrainSlot?
var activeSlotPath: String?
atexit {
    activeSlot?.release()
}
let slotHandler: @convention(c) (Int32) -> Void = { sig in
    if let path = activeSlotPath {
        Hardening.releaseSlot(at: URL(fileURLWithPath: path))
    }
    _exit(128 + sig)
}
signal(SIGTERM, slotHandler)
signal(SIGINT, slotHandler)

switch Hardening.acquireSlot() {
case .success(let slot):
    activeSlot = slot
    activeSlotPath = slot.directory.path
case .failure(let refusal):
    FileHandle.standardError.write(Data("sl: \(refusal.message)\n".utf8))
    exit(1)
}

// --- Overlay run -------------------------------------------------------
let code = MainActor.assumeIsolated { () -> Int32 in
    let screens = OverlayGeometry.runScreens(all: spec.allDisplays)
    guard let lane = OverlayGeometry.lane(
        on: screens, height: OverlayGeometry.laneHeight) else {
        FileHandle.standardError.write(Data("sl: no display attached\n".utf8))
        return ExitReason.noDisplay.exitCode
    }

    // `--model` preflight: a missing or unloadable asset is a usage
    // error — stderr + exit 2 before any window opens. The loaded,
    // lane-height-normalized node is handed to the renderer once.
    var model: ModelAsset.Loaded?
    if let path = spec.model {
        // Bare `loco` resolves to the bundled share/sl/models/loco.usdz;
        // anything else is a user-supplied path.
        let resolved = path == "loco"
            ? modelAssetURL(named: "loco.usdz")?.path ?? path
            : path
        do {
            model = try ModelAsset.loadTrain(
                at: resolved, targetHeight: OverlayGeometry.laneHeight)
        } catch {
            FileHandle.standardError.write(Data(
                "sl: cannot load model '\(path)': \(error)\n".utf8))
            exit(2)
        }
    }

    // Dock zones the train hops over, in lane-local x — one per
    // bottom-Docked screen, empty when no Dock is present.
    let dockZones = OverlayGeometry.dockZones(on: screens, lane: lane)

    let ui = RunUI()
    let base: any FrameDriver

    if spec.allDisplays {
        let stage = MultiScreenTrain(
            lane: lane, fly: spec.fly, dock: dockZones)
        for screen in screens {
            let strip = OverlayGeometry.bottomStrip(
                on: screen, height: OverlayGeometry.laneHeight)
            let window = OverlayWindow(frame: strip)
            let content = NSView(frame: NSRect(origin: .zero, size: strip.size))
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor
            let node = TrainGlyph.makeView()
            node.frame = NSRect(origin: .zero, size: TrainGlyph.size)
            content.addSubview(node)
            window.contentView = content
            window.orderFrontRegardless()
            window.setStealth(spec.stealth)
            ui.windows.append(window)
            stage.attach(screenFrame: screen.frame, node: node)
        }
        base = StageDriver(stage: stage)
    } else {
        let renderer = RendererFactory.make(
            spec: spec, stripWidth: lane.width, model: model,
            dock: dockZones)
        let window = OverlayWindow(frame: lane)
        window.contentView = renderer.makeView(
            in: NSRect(origin: .zero, size: lane.size), spec: spec)
        window.orderFrontRegardless()
        window.setStealth(spec.stealth)
        ui.windows.append(window)
        base = RendererDriver(renderer: renderer)
    }

    // `-s` playback: chuff loop, whistles, `-a` screams. Freeze/shot
    // mode stays silent — it exists for screenshots, not ears.
    let audio = spec.freeze == nil
        ? AudioEngine(spec: spec, duration: base.duration)
        : nil
    let driver = OverlayDriver(base: base, audio: audio, ui: ui)

    return RunLoop.run(spec: spec, overlay: ui.windows[0], driver: driver)
}

exit(code)
