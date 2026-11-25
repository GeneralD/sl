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

    /// `--all`: one overlay window per display; the train crosses every
    /// screen in global coordinates. `false` = frontmost screen only.
    public var allDisplays: Bool = false

    /// `-F` flight: the train climbs the upstream `y = x/7` diagonal and
    /// exits toward the upper-left instead of running the lane to its end.
    public var fly: Bool = false

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
        // Skeleton: bare `sl`, `--all`, `-F` and `--freeze` are valid; the
        // rest of the classic flag surface is feature work (#11).
        var i = 0
        var unknown: [String] = []
        while i < args.count {
            let arg = args[i]
            if arg == "--all" {
                spec.allDisplays = true
                i += 1
            } else if arg == "-F" {
                spec.fly = true
                i += 1
            } else if arg == "--freeze", i + 1 < args.count,
                      let t = TimeInterval(args[i + 1]) {
                spec.freezeAt = t
                i += 2
            } else {
                unknown.append(arg)
                i += 1
            }
        }
        if !unknown.isEmpty { spec.parseError = "unimplemented flag surface" }
        return spec
    }
}
