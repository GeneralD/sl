import Foundation

/// Why a run ended, mapped to the process exit code `sl` returns.
/// Pure value type in SLCore so slChecks pins the mapping without a
/// window server.
public enum ExitReason: Int32, Sendable {
    /// The train crossed, `--duration` elapsed, or a `--freeze` frame
    /// was held and released normally.
    case finished = 0
    /// No display attached to draw the lane on.
    case noDisplay = 1
    /// The watchdog hard stop fired (run length + grace exceeded).
    case watchdog = 3
    /// SIGINT honored via `-e` (~128 + SIGINT).
    case interrupted = 130

    /// The status `exit(3)` sees.
    public var exitCode: Int32 { rawValue }
}
