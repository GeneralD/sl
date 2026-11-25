import Foundation

/// What a single `sl` invocation resolves to — the parsed result of the
/// classic flag surface. Pure value type; all argv normalization lives at
/// this boundary.
public struct RunSpec: Sendable {
    /// Informational flags: the run never starts, the CLI answers and exits.
    public var versionRequested: Bool = false
    public var helpRequested: Bool = false

    /// Classic short flags (see `sl.1`).
    public var accident: Bool = false
    public var c51: Bool = false
    public var disco: Bool = false
    public var allowInterrupt: Bool = false
    public var fly: Bool = false
    public var tgv: Bool = false
    public var little: Bool = false
    public var sound: Bool = false

    /// `-<n>` trailing cars, 1...10. Default run pulls one car.
    public var cars: Int = 1

    /// `-w` gust factor on the run speed; 1.0 is the calm default.
    public var speedFactor: Double = 1.0

    /// Long flags.
    public var model: String? = nil
    public var allDisplays: Bool = false

    /// `scripts/shot` mode: render the frame at this offset in seconds and
    /// hold the window open until SIGTERM. `nil` = normal timed run.
    public var freeze: Double? = nil

    public var stealth: Bool = false
}

/// Why argv failed to parse. `message` is the one-line reason the CLI
/// prints before the usage text.
public enum ParseError: Error, Sendable, CustomStringConvertible {
    case unknownFlag(String)
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidValue(String, String)
    case invalidCarCount(Int)

    public var message: String {
        switch self {
        case .unknownFlag(let flag): return "unknown flag: \(flag)"
        case .unexpectedArgument(let arg): return "unexpected argument: \(arg)"
        case .missingValue(let flag): return "\(flag) requires a value"
        case .invalidValue(let flag, let value):
            return "\(flag): invalid value '\(value)'"
        case .invalidCarCount(let n):
            return "invalid car count \(n) (expected 1-10)"
        }
    }

    public var description: String { message }
}

public extension RunSpec {
    /// Flag table matching `sl.1`; `-h` prints this.
    static func usage() -> String {
        """
        usage: sl [-aceFGlhlsvw] [-<number-of-cars>] [--all] [--model <file>] [--freeze <seconds>] [--stealth]
               sl --help | --version

        flags:
          -a            an accident seems to happen
          -c            C51 locomotive instead of D51
          -d            disco mode
          -e            allow interruption by Ctrl+C
          -F            fly like the Galaxy Express 999
          -G            French TGV
          -h            print this flag table
          -l            little version
          -s            chuff and whistle
          -v            print version
          -w            windy: moves faster
          -<n>          pull n trailing cars (1-10)
          --all         traverse every connected display
          --model FILE  load a .usdz/.scn/.dae locomotive
          --freeze SEC  render one frozen frame and hold
          --stealth     hide from screen sharing
          --version     print version
        """
    }

    /// Hand-rolled getopt-style parse. `args` is the full argv including
    /// the program name; an empty argv yields the valid default spec.
    /// Clustered shorts (`-alF`) and `-<n>` car counts (1...10) are
    /// supported; anything unrecognized is a `ParseError`.
    static func parse(_ args: [String]) -> Result<RunSpec, ParseError> {
        var spec = RunSpec()
        var rest = Array(args.dropFirst())

        func nextValue(for flag: String) -> Result<String, ParseError> {
            guard !rest.isEmpty else { return .failure(.missingValue(flag)) }
            let value = rest.removeFirst()
            guard !value.isEmpty else { return .failure(.missingValue(flag)) }
            return .success(value)
        }

        func setCars(_ n: Int) -> ParseError? {
            guard (1...10).contains(n) else { return .invalidCarCount(n) }
            spec.cars = n
            return nil
        }

        while !rest.isEmpty {
            let arg = rest.removeFirst()
            guard arg.hasPrefix("-"), arg != "-" else {
                return .failure(.unexpectedArgument(arg))
            }

            if arg.hasPrefix("--") {
                let body = String(arg.dropFirst(2))
                let parts = body.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0])
                let inline = parts.count > 1 ? String(parts[1]) : nil
                switch name {
                case "help": spec.helpRequested = true
                case "version": spec.versionRequested = true
                case "all": spec.allDisplays = true
                case "stealth": spec.stealth = true
                case "model", "freeze":
                    let value: String
                    if let inline {
                        guard !inline.isEmpty else { return .failure(.missingValue("--\(name)")) }
                        value = inline
                    } else {
                        switch nextValue(for: "--\(name)") {
                        case .success(let v): value = v
                        case .failure(let e): return .failure(e)
                        }
                    }
                    if name == "model" {
                        spec.model = value
                    } else {
                        guard let seconds = Double(value) else {
                            return .failure(.invalidValue("--freeze", value))
                        }
                        spec.freeze = seconds
                    }
                default:
                    return .failure(.unknownFlag("--\(name)"))
                }
                continue
            }

            // Short cluster: flag letters plus an optional digit run for
            // the car count (`-3`, `-10`, `-a3`).
            var digitRun = ""
            for ch in arg.dropFirst() {
                if ch.isNumber {
                    digitRun.append(ch)
                    continue
                }
                if !digitRun.isEmpty {
                    let n = Int(digitRun) ?? 0
                    if let error = setCars(n) { return .failure(error) }
                    digitRun = ""
                }
                switch ch {
                case "a": spec.accident = true
                case "c": spec.c51 = true
                case "d": spec.disco = true
                case "e": spec.allowInterrupt = true
                case "F": spec.fly = true
                case "G": spec.tgv = true
                case "h": spec.helpRequested = true
                case "l": spec.little = true
                case "s": spec.sound = true
                case "v": spec.versionRequested = true
                case "w": spec.speedFactor = 1.5
                default: return .failure(.unknownFlag("-\(ch)"))
                }
            }
            if !digitRun.isEmpty {
                let n = Int(digitRun) ?? 0
                if let error = setCars(n) { return .failure(error) }
            }
        }
        return .success(spec)
    }
}
