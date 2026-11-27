import AppKit
import CoreGraphics
import Darwin
import Foundation

/// Runtime hardening for overlay runs, wired by `sl`'s main.swift:
/// the concurrency cap, headless refusal, `--stealth` capture
/// exclusion, and the end-of-run fade-out. Slot claims are atomic
/// `mkdir`s so concurrent trains can't race; a dead holder's slot is
/// reclaimed, keeping the cap stale-proof.
public enum Hardening {
    /// Maximum concurrent trains on one machine — more is a self-DoS.
    public static let maxConcurrentTrains = 5

    /// Seconds the overlay takes to fade before the run closes.
    public static let fadeOutDuration: TimeInterval = 0.2

    /// Seconds the overlay fades in on launch: the window orders in
    /// invisible so SceneKit's first unpainted drawable can never
    /// flash on screen, then ramps up while the train is still
    /// off-screen entering.
    public static let fadeInDuration: TimeInterval = 0.25

    /// One claimed concurrency slot. `release` is idempotent and uses
    /// only async-signal-safe calls so the SIGTERM path can run it.
    public struct TrainSlot: Sendable {
        public let directory: URL

        public func release() {
            Hardening.releaseSlot(at: directory)
        }
    }

    /// Default slot root: one directory per uid under the shared temp dir.
    public static func slotRoot(uid: uid_t = getuid()) -> URL {
        URL(fileURLWithPath: "/tmp/sl-\(uid)-slots", isDirectory: true)
    }

    /// Why a slot claim was refused; `message` is what `sl` prints.
    public struct SlotRefusal: Error, Sendable, CustomStringConvertible {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { message }
    }

    /// Claims one of `maxConcurrentTrains` slots by atomic `mkdir` —
    /// `EEXIST` means taken. A slot whose recorded pid is dead is stale
    /// and gets reclaimed before the next slot is tried. All slots held
    /// → `.failure(SlotRefusal("too many trains"))`.
    public static func acquireSlot(root: URL? = nil) -> Result<TrainSlot, SlotRefusal> {
        let root = root ?? slotRoot()
        try? FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        for n in 0..<maxConcurrentTrains {
            let dir = root.appendingPathComponent("slot-\(n)", isDirectory: true)
            if claim(dir) {
                return .success(TrainSlot(directory: dir))
            }
        }
        return .failure(SlotRefusal("too many trains"))
    }

    /// Removes a slot directory (pid file, then the dir itself) with
    /// async-signal-safe calls only.
    public static func releaseSlot(at directory: URL) {
        _ = unlink(directory.appendingPathComponent("pid").path)
        _ = rmdir(directory.path)
    }

    /// `nil` when a run can present a window; otherwise the one-line
    /// refusal reason `sl` prints to stderr before exiting nonzero.
    public static func headlessRefusal(hasWindowServerSession: Bool,
                                       screenCount: Int) -> String? {
        guard hasWindowServerSession else { return "no window server session" }
        guard screenCount > 0 else { return "no usable screen" }
        return nil
    }

    /// Live probe of the two facts `headlessRefusal` judges. The
    /// `SL_HEADLESS=1` env var forces the refusal so the headless lane
    /// can be exercised without an SSH session.
    public static func liveHeadlessRefusal() -> String? {
        let forced = ProcessInfo.processInfo.environment["SL_HEADLESS"] == "1"
        let session = !forced && CGSessionCopyCurrentDictionary() != nil
        return headlessRefusal(hasWindowServerSession: session,
                               screenCount: NSScreen.screens.count)
    }

    /// Progress of the end-of-run fade: window alpha goes 1 → 0 over
    /// `duration`, then the run closes. Stepped explicitly — never a
    /// wall-clock sleep — so checks drive it with fixed deltas.
    public struct FadeOut: Sendable {
        public let duration: TimeInterval
        public private(set) var elapsed: TimeInterval = 0

        public init(duration: TimeInterval = Hardening.fadeOutDuration) {
            self.duration = duration
        }

        /// Advance by `dt` seconds; returns the alpha to apply (1 at the
        /// start, 0 once `duration` has elapsed, clamped after).
        @discardableResult
        public mutating func advance(by dt: TimeInterval) -> CGFloat {
            elapsed = min(elapsed + max(dt, 0), duration)
            let progress = duration > 0 ? elapsed / duration : 1
            return CGFloat(1 - progress)
        }

        public var isFinished: Bool { elapsed >= duration }
    }

    // MARK: - slot internals

    /// `mkdir` is the atomic claim: success means the slot is ours,
    /// `EEXIST` means taken or stale. On `EEXIST` a dead holder's slot
    /// is reclaimed and the claim retried once.
    private static func claim(_ dir: URL) -> Bool {
        if mkdir(dir.path, 0o700) == 0 {
            writePid(to: dir)
            return true
        }
        guard errno == EEXIST, reclaimIfStale(dir),
              mkdir(dir.path, 0o700) == 0 else { return false }
        writePid(to: dir)
        return true
    }

    /// Grace period before a pid-less slot counts as stale: a live
    /// claimant writes its pid microseconds after the `mkdir`, so a
    /// missing/unparseable pid is only stale once this has passed.
    private static let claimGracePeriod: TimeInterval = 5

    /// A slot is stale when its pid names a dead process, or when it
    /// has no readable pid and is older than `claimGracePeriod`.
    private static func reclaimIfStale(_ dir: URL) -> Bool {
        let pidPath = dir.appendingPathComponent("pid")
        if let text = try? String(contentsOf: pidPath, encoding: .utf8),
           let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid > 0 {
            guard kill(pid, 0) != 0, errno == ESRCH else { return false }
        } else {
            guard let modified = try? FileManager.default
                .attributesOfItem(atPath: dir.path)[.modificationDate] as? Date,
                  Date().timeIntervalSince(modified) > claimGracePeriod
            else { return false }
        }
        try? FileManager.default.removeItem(at: dir)
        return true
    }

    private static func writePid(to dir: URL) {
        try? "\(getpid())\n".write(
            to: dir.appendingPathComponent("pid"),
            atomically: false, encoding: .utf8)
    }
}
