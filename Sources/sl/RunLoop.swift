import AppKit
import Foundation
import OverlayKit
import SLCore

/// The per-frame seam the run loop drives: one crossing's expected
/// duration, the advance callback (`onFrame` returns false once the
/// train has exited), and a fixed-frame render for `--freeze`.
/// `Renderer` and `MultiScreenTrain` each get a thin adapter in
/// `main.swift`; trajectory math stays behind this boundary.
@MainActor
public protocol FrameDriver {
    /// Wall-clock seconds the driver expects one crossing to take.
    var duration: TimeInterval { get }

    /// Advance the scene to `t` seconds since train-enter; return false
    /// when the run is done.
    var onFrame: (TimeInterval) -> Bool { get }

    /// Pin the scene to `t` (`--freeze` shot mode).
    func render(at t: TimeInterval)
}

/// The process contract: NSApplication run, run duration, watchdog,
/// `--freeze` hold, SIGINT policy and the exit code. `main.swift` only
/// parses argv and builds the overlay + driver.
public enum RunLoop {
    /// Run-length cap when `--duration` is absent; the driver's own
    /// (shorter) crossing length always wins.
    public static let defaultDuration: TimeInterval = 10

    /// Watchdog grace past the run length before the hard stop.
    public static let watchdogGrace: TimeInterval = 30

    /// Frame cadence for the run timer.
    public static let frameInterval: TimeInterval = 1.0 / 120

    /// Terminal state the frame timer writes for `app.run()` to return.
    @MainActor
    private final class Outcome {
        var reason: ExitReason = .finished
    }

    /// Blocks until the run ends and returns the process exit code.
    /// Freeze mode never returns on its own — `scripts/shot` kills the
    /// process.
    @MainActor
    public static func run(spec: RunSpec, overlay: OverlayWindow,
                           driver: some FrameDriver) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Classic contract: Ctrl+C is ignored unless -e asked for it.
        // With -e the disposition installed by main (the slot-releasing
        // handler, or the default) stands and the process dies by
        // SIGINT (~130).
        if !spec.allowInterrupt {
            signal(SIGINT, SIG_IGN)
        }

        overlay.orderFrontRegardless()

        if let freezeAt = spec.freeze {
            driver.render(at: freezeAt)
            app.run() // held for scripts/shot; SIGTERM exits
            return ExitReason.finished.exitCode
        }

        // Never outlive the driver's own crossing; --duration only
        // shortens it.
        let limit = min(spec.duration ?? defaultDuration, driver.duration)
        let start = Date()
        let hardStop = start.addingTimeInterval(limit + watchdogGrace)
        let outcome = Outcome()

        // One MainActor-isolated tick (Sendable, so the @Sendable timer
        // block can capture it): returns false once the run is over.
        let step: @MainActor () -> Bool = {
            let t = Date().timeIntervalSince(start)
            let reason: ExitReason?
            if Date() > hardStop {
                reason = .watchdog
            } else if !driver.onFrame(t) || t >= limit {
                reason = .finished
            } else {
                reason = nil
            }
            guard let reason else { return true }
            outcome.reason = reason
            app.stop(nil)
            // stop() only requests the loop to exit — post a dummy
            // event so app.run() returns promptly (Gemini review on #57:
            // terminate() would exit the process before the exit code
            // can be returned).
            if let event = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, subtype: 0, data1: 0, data2: 0) {
                app.postEvent(event, atStart: false)
            }
            return false
        }

        Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { timer in
            if !MainActor.assumeIsolated({ step() }) {
                timer.invalidate()
            }
        }

        app.run()
        return outcome.reason.exitCode
    }
}
