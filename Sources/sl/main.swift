import AppKit
import OverlayKit
import SLCore
import TrainScene

// sl — a 3D steam locomotive that runs across your desktop.
// Skeleton wiring: flag surface works headless; the overlay run is what
// the fleet builds out behind this same shape.

let spec = RunSpec.parse(ProcessInfo.processInfo.arguments)

if spec.versionRequested {
    print(SLVersion.current)
    exit(0)
}

if spec.helpRequested {
    print(RunSpec.usage)
    exit(0)
}

if let error = spec.parseError {
    FileHandle.standardError.write(Data("sl: \(error)\n".utf8))
    FileHandle.standardError.write(Data(RunSpec.usage.utf8))
    exit(2)
}

// --- Overlay run -------------------------------------------------------
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var freezeMode = false
MainActor.assumeIsolated {
    guard let screen = OverlayGeometry.frontmostScreen() else {
        FileHandle.standardError.write(Data("sl: no display attached\n".utf8))
        exit(1)
    }
    let laneFrame = OverlayGeometry.bottomStrip(on: screen, height: 180)
    let window = OverlayWindow(frame: laneFrame)
    let renderer = PlaceholderRenderer(
        spec: spec, stripWidth: laneFrame.width, stripHeight: laneFrame.height)
    window.contentView = renderer.makeView(
        in: NSRect(origin: .zero, size: laneFrame.size), spec: spec)
    window.orderFrontRegardless()

    if let freeze = spec.freezeAt {
        freezeMode = true
        renderer.render(at: freeze)
    } else {
        let start = Date()
        let hardStop = start.addingTimeInterval(renderer.duration + 30)
        Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { timer in
            let alive = MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(start)
                return renderer.step(to: t) && Date() <= hardStop
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
