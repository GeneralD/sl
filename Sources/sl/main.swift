import AppKit
import OverlayKit
import SLCore
import TrainScene

// sl — a 3D steam locomotive that runs across your desktop.
// Skeleton wiring: flag surface works headless; the overlay run is what
// the fleet builds out behind this same shape.

/// Run-scoped UI state shared between the setup block and the frame
/// timer. `@MainActor` makes it `Sendable`, so the `@Sendable` timer
/// closure can capture it safely.
@MainActor
private final class RunUI {
    var windows: [OverlayWindow] = []
    var fade: Hardening.FadeOut?
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
// normal exit via atexit, SIGTERM/SIGINT via the signal handler.
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
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var freezeMode = false
MainActor.assumeIsolated {
    let screens = OverlayGeometry.runScreens(all: spec.allDisplays)
    guard let lane = OverlayGeometry.lane(
        on: screens, height: OverlayGeometry.laneHeight) else {
        FileHandle.standardError.write(Data("sl: no display attached\n".utf8))
        exit(1)
    }

    // `--model` preflight: a missing or unloadable asset is a usage
    // error — stderr + exit 2 before any window opens. The loaded,
    // lane-height-normalized node is handed to the renderer once.
    var model: ModelAsset.Loaded?
    if let path = spec.model {
        do {
            model = try ModelAsset.loadTrain(
                at: path, targetHeight: OverlayGeometry.laneHeight)
        } catch {
            FileHandle.standardError.write(Data(
                "sl: cannot load model '\(path)': \(error)\n".utf8))
            exit(2)
        }
    }

    // The run's per-frame driver: the single-display renderer, or the
    // multi-display stage under --all (one window per screen).
    let duration: TimeInterval
    let step: @MainActor (TimeInterval) -> Bool
    let freeze: @MainActor (TimeInterval) -> Void
    let ui = RunUI()

    if spec.allDisplays {
        let stage = MultiScreenTrain(lane: lane, fly: spec.fly)
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
        duration = stage.duration
        step = { t in
            stage.update(t: t)
            return !stage.finished
        }
        freeze = { stage.update(t: $0) }
    } else {
        let renderer = RendererFactory.make(
            spec: spec, stripWidth: lane.width, model: model)
        let window = OverlayWindow(frame: lane)
        window.contentView = renderer.makeView(
            in: NSRect(origin: .zero, size: lane.size), spec: spec)
        window.orderFrontRegardless()
        window.setStealth(spec.stealth)
        ui.windows.append(window)
        duration = renderer.duration
        step = { renderer.step(to: $0) }
        freeze = { renderer.render(at: $0) }
    }

    // `-s` playback: chuff loop, whistles, `-a` screams. Freeze/shot
    // mode stays silent — it exists for screenshots, not ears.
    let audio = spec.freeze == nil
        ? AudioEngine(spec: spec, duration: duration)
        : nil

    if let freezeAt = spec.freeze {

        freezeMode = true
        freeze(freezeAt)
    } else {
        let start = Date()
        let hardStop = start.addingTimeInterval(duration + 30)
        Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { timer in
            // 1 = fade finished, close and exit; 0 = keep ticking.
            let done = MainActor.assumeIsolated { () -> Int in
                if var f = ui.fade {
                    let alpha = f.advance(by: 1.0 / 120)
                    for window in ui.windows { window.alphaValue = alpha }
                    ui.fade = f
                    return f.isFinished ? 1 : 0
                }
                let t = Date().timeIntervalSince(start)
                let running = step(t)
                audio?.update(t: t, finished: !running)
                // Hold for the exit whistle's tail after the train is
                // gone — the fade (and exit) waits for it so the note
                // isn't clipped.
                let tail = audio?.tailRemaining(t: t) ?? 0
                guard running || tail > 0, Date() <= hardStop else {
                    ui.fade = Hardening.FadeOut()
                    return 0
                }
                return 0
            }
            guard done == 1 else { return }
            timer.invalidate()
            MainActor.assumeIsolated {
                for window in ui.windows { window.close() }
            }
            exit(0)
        }
    }
}

if freezeMode {
    RunLoop.main.run() // held for scripts/shot; SIGTERM exits
} else {
    app.run()
}
