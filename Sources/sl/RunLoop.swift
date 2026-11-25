import AppKit
import CoreVideo
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

    /// C-convention trampoline between CVDisplayLink's callback thread
    /// and the main-actor step. `@unchecked Sendable`: `step` and
    /// `onDone` are installed before the link starts firing, and `fire`
    /// hops to the main queue before touching either.
    private final class DisplayLinkTrampoline: @unchecked Sendable {
        let step: @MainActor () -> Bool
        var onDone: (@Sendable () -> Void)?
        /// At most one queued step: if the main thread stalls (a slow
        /// render), vsync callbacks keep arriving on the link thread —
        /// without this flag they would pile up unboundedly and burst-
        /// render afterward. Latest-t wins because `step` reads wall
        /// time, not a per-callback payload.
        private let pendingLock = NSLock()
        private var pending = false

        init(step: @escaping @MainActor () -> Bool) {
            self.step = step
        }

        /// The display-link thread entry point — a plain C function, so
        /// no captures; the trampoline arrives through `userInfo`.
        static let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
            guard let userInfo else { return kCVReturnInvalidArgument }
            Unmanaged<DisplayLinkTrampoline>.fromOpaque(userInfo)
                .takeUnretainedValue().fire()
            return kCVReturnSuccess
        }

        /// Queue one main-actor step; when it reports the run is over,
        /// stop the link so no further callbacks pile up. `step` and
        /// `onDone` are captured by value — the queued closure is
        /// transient and must not keep the trampoline alive.
        func fire() {
            pendingLock.lock()
            guard !pending else {
                pendingLock.unlock()
                return
            }
            pending = true
            pendingLock.unlock()
            let step = self.step
            let onDone = self.onDone
            DispatchQueue.main.async {
                let keepGoing = MainActor.assumeIsolated { step() }
                self.pendingLock.lock()
                self.pending = false
                self.pendingLock.unlock()
                if !keepGoing { onDone?() }
            }
        }
    }

    /// Display-synced frame clock. CVDisplayLink fires once per display
    /// refresh — locked to the panel's current rate, so ProMotion
    /// panels get their full refresh with no drift — and never busy-
    /// spins: it is driven by the hardware's vsync, not a poll.
    /// `init` returns nil when no display link can be created; the
    /// caller then falls back to the Timer path.
    ///
    /// The CVDisplayLink C API is deprecated in the macOS 15 SDK (Apple
    /// points at `NSView.displayLink`, macOS 14+) but remains the only
    /// vsync source reachable from a `macOS(.v13)` deployment target —
    /// see DECISIONS.md [25].
    private final class DisplayClock: @unchecked Sendable {
        private var link: CVDisplayLink?
        private let trampoline: DisplayLinkTrampoline
        private let context: UnsafeMutableRawPointer

        init?(step: @escaping @MainActor () -> Bool) {
            let trampoline = DisplayLinkTrampoline(step: step)
            // Retained for the link's lifetime: the C callback reaches
            // the trampoline through this pointer on the link thread.
            let context = Unmanaged.passRetained(trampoline).toOpaque()
            var created: CVDisplayLink?
            guard CVDisplayLinkCreateWithActiveCGDisplays(&created) == kCVReturnSuccess,
                  let created,
                  CVDisplayLinkSetOutputCallback(
                      created, DisplayLinkTrampoline.callback, context
                  ) == kCVReturnSuccess,
                  CVDisplayLinkStart(created) == kCVReturnSuccess
            else {
                if let created { CVDisplayLinkStop(created) }
                Unmanaged<DisplayLinkTrampoline>.fromOpaque(context).release()
                return nil
            }
            self.trampoline = trampoline
            self.link = created
            self.context = context
            trampoline.onDone = { [weak self] in self?.invalidate() }
        }

        /// Stop vsync callbacks and release the trampoline's extra
        /// retain. Idempotent — the link's last `step` and the post-run
        /// cleanup can both land here.
        func invalidate() {
            guard let link else { return }
            CVDisplayLinkStop(link)
            self.link = nil
            Unmanaged<DisplayLinkTrampoline>.fromOpaque(context).release()
        }
    }

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

        // Vsync pacing first; the Timer is the fallback when no display
        // link can be created (FramePacing owns the decision).
        let clock = DisplayClock(step: step)
        switch FramePacing.source(displayLinkAvailable: clock != nil) {
        case .displayLink:
            app.run()
            clock?.invalidate()
        case .timer:
            let timer = Timer.scheduledTimer(
                withTimeInterval: FramePacing.fallbackInterval,
                repeats: true) { timer in
                if !MainActor.assumeIsolated({ step() }) {
                    timer.invalidate()
                }
            }
            app.run()
            timer.invalidate()
        }
        return outcome.reason.exitCode
    }
}
