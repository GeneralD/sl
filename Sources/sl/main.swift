import AppKit
import OverlayKit
import SLCore
import TrainScene

// sl — a 3D steam locomotive that runs across your desktop.
// main.swift: parse argv, build the overlay windows and the frame
// driver, then hand the process contract to RunLoop.

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

// The run's per-frame driver: the single-display renderer, or the
// multi-display stage under --all (one window per screen).
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
}

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

let code = MainActor.assumeIsolated { () -> Int32 in
    let screens = OverlayGeometry.runScreens(all: spec.allDisplays)
    guard let lane = OverlayGeometry.lane(
        on: screens, height: OverlayGeometry.laneHeight) else {
        FileHandle.standardError.write(Data("sl: no display attached\n".utf8))
        return ExitReason.noDisplay.exitCode
    }

    if spec.allDisplays {
        let stage = MultiScreenTrain(lane: lane)
        var windows: [OverlayWindow] = []
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
            windows.append(window)
        }
        return RunLoop.run(
            spec: spec, overlay: windows[0], driver: StageDriver(stage: stage))
    }

    let renderer = RendererFactory.make(spec: spec, stripWidth: lane.width)
    let window = OverlayWindow(frame: lane)
    window.contentView = renderer.makeView(
        in: NSRect(origin: .zero, size: lane.size), spec: spec)
    window.orderFrontRegardless()
    return RunLoop.run(
        spec: spec, overlay: window, driver: RendererDriver(renderer: renderer))
}

exit(code)
