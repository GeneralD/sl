import Foundation

/// What a single `sl` invocation resolves to — the parsed result of the
/// classic flag surface. Pure value type; all argv normalization lives at
/// this boundary.
public struct RunSpec: Sendable {
    public var versionRequested: Bool = false
    public var helpRequested: Bool = false
    public var parseError: String? = nil

    /// `scripts/shot` mode: render the frame at this offset in seconds and
    /// hold the window open until SIGTERM. `nil` = normal timed run.
    public var freezeAt: TimeInterval? = nil

    /// The flag table is the single source of truth for the classic `sl`
    /// surface; each feature extends it, never the parser call sites.
    public static let usage = """
    usage: sl [-acdeFGlw] [-<number-of-cars>] [-s] [-v]
           sl --help | --version | --model <file> | --all | --freeze <seconds>
    """

    /// First-pass skeleton parser: handles -v/--version/--help and the
    /// catch-all error path. The full flag matrix is feature work.
    public static func parse(_ argv: [String]) -> RunSpec {
        let args = Array(argv.dropFirst())
        var spec = RunSpec()
        if args.contains("-v") || args.contains("--version") { spec.versionRequested = true }
        if args.contains("-h") || args.contains("--help") { spec.helpRequested = true }
        if spec.versionRequested || spec.helpRequested { return spec }
        if let i = args.firstIndex(of: "--freeze"), i + 1 < args.count,
           let t = TimeInterval(args[i + 1]) {
            spec.freezeAt = t
            return spec
        }
        // Skeleton: bare `sl` is valid (the default run). Unknown flags
        // still error — the full classic flag surface is feature work.
        if !args.isEmpty { spec.parseError = "unimplemented flag surface" }
        return spec
    }
}
