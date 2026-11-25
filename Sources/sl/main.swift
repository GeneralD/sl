import AppKit
import OverlayKit
import SLCore
import TrainScene

// sl — a 3D steam locomotive that runs across your desktop.
// Skeleton wiring: flag surface works headless; the overlay run is what
// the fleet builds out behind this same shape.

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
        duration = renderer.duration
        step = { renderer.step(to: $0) }
        freeze = { renderer.render(at: $0) }
    }

    if let freezeAt = spec.freeze {

        freezeMode = true
        freeze(freezeAt)
    } else {
        let start = Date()
        let hardStop = start.addingTimeInterval(duration + 30)
        Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { timer in
            let alive = MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(start)
                return step(t) && Date() <= hardStop
            }
            if !alive {
                timer.invalidate()
                exit(0)
            }
        }
    }
}

if freezeMode {
    RunLoop.main.run() // held for scripts/shot; SIGTERM exits
} else {
    app.run()
}
