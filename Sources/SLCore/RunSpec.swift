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
    public var disco: Bool = false
    public var allowInterrupt: Bool = false
    public var fly: Bool = false
    public var little: Bool = false
    public var sound: Bool = false

    /// Trailing cars: `-<n>` pulls 1...10 (the classic contract);
    /// `--cars <n>` accepts 0...50 — 0 runs the locomotive light.
    public var cars: Int = 1

    /// `-w` gust factor on the run speed; 1.0 is the calm default.
    public var speedFactor: Double = 1.0

    /// Long flags.
    public var model: String? = nil
    public var allDisplays: Bool = false

    /// `scripts/shot` mode: render the frame at this offset in seconds and
    /// hold the window open until SIGTERM. `nil` = normal timed run.
    public var freeze: Double? = nil

    /// `--duration SEC`: cap the run at SEC seconds. `nil` = the RunLoop
    /// default (10s, never past the driver's own crossing length).
    public var duration: TimeInterval? = nil

    /// `--scale <f>`: multiplier on the default near-screen-filling
    /// train size. 1 is the tuned default; values must be positive.
    public var scale: Double = 1.0

    /// `--angle <deg>`: camera azimuth for the 3/4 view — 0 is the
    /// classic flat side-on lane; the default swings the camera
    /// toward the loco's front so it runs diagonally on screen.
    public var viewAngle: Double = 55

    /// `--color <name|deg>`: respray the consist's colored materials.
    /// Each component is an absolute override — nil keeps the
    /// material's own value, so a named hue keeps its shading while a
    /// neutral name (black, gray) only drops saturation.
    /// The default livery is matte black with gold fittings — the
    /// signature look; `factory`/`none` restores the as-built finish.
    public struct Livery: Sendable, Equatable {
        public var hue: Double?        // 0–1 color wheel position
        public var saturation: Double?
        public var brightness: Double?

        /// Two-tone paintwork: colored materials whose own hue falls in
        /// `hueRange` repaint to this accent instead of the body colour
        /// — matte-black boiler with gold domes and bands.
        public struct Accent: Sendable, Equatable {
            public var hue: Double
            public var saturation: Double
            public var brightness: Double
            /// Material hues (0–1 wheel) inside this band take the accent.
            public var hueRange: ClosedRange<Double>
        }
        public var accent: Accent? = nil
        /// Matte finish: resprayed materials lose their specular
        /// response, so `black` reads as stove paint, not vinyl.
        public var matte: Bool = false

        /// Named resprays: hue names keep each part's own
        /// saturation/brightness; the neutrals pull them instead.
        public static let named: [String: Livery] = [
            "red":     Livery(hue: 0.00),
            "crimson": Livery(hue: 0.96),
            "orange":  Livery(hue: 0.07),
            "yellow":  Livery(hue: 0.15),
            "green":   Livery(hue: 0.33),
            "teal":    Livery(hue: 0.50),
            "blue":    Livery(hue: 0.60),
            "indigo":  Livery(hue: 0.72),
            "purple":  Livery(hue: 0.78),
            "pink":    Livery(hue: 0.92),
            "black":   Livery(
                saturation: 0.05, brightness: 0.16,
                accent: Accent(hue: 0.105, saturation: 0.72,
                               brightness: 0.85,
                               hueRange: 0.0...0.17),
                matte: true),
            "gray":    Livery(saturation: 0.03, brightness: 0.45),
            "grey":    Livery(saturation: 0.03, brightness: 0.45),
        ]
    }
    public var livery: Livery? = Livery.named["black"]

    public var stealth: Bool = false

    /// `-a` requests the accident: the visual panic (screamer sprites,
    /// rocking loco) lands first and the audio engine reads this to
    /// layer screams on top — sound stays gated by `sound` (`-s`).
    public var wantScreams: Bool { accident }
}

/// Why argv failed to parse. `message` is the one-line reason the CLI
/// prints before the usage text.
public enum ParseError: Error, Sendable, CustomStringConvertible {
    case unknownFlag(String)
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidValue(String, String)
    case invalidCarCount(Int, expected: String)

    public var message: String {
        switch self {
        case .unknownFlag(let flag): return "unknown flag: \(flag)"
        case .unexpectedArgument(let arg): return "unexpected argument: \(arg)"
        case .missingValue(let flag): return "\(flag) requires a value"
        case .invalidValue(let flag, let value):
            return "\(flag): invalid value '\(value)'"
        case .invalidCarCount(let n, let expected):
            return "invalid car count \(n) (expected \(expected))"
        }
    }

    public var description: String { message }
}

public extension RunSpec {
    /// Flag table matching `sl.1`; `-h` prints this.
    static func usage() -> String {
        """
        usage: sl [-adeFhlsvw] [-<number-of-cars>] [--cars <n>] [--all] [--model <file>] [--freeze <seconds>] [--duration <seconds>] [--scale <factor>] [--angle <deg>] [--color <name|deg>] [--stealth]
               sl --help | --version

        flags:
          -a            an accident seems to happen
          -d            disco mode
          -e            allow interruption by Ctrl+C
          -F            fly like the Galaxy Express 999
          -h            print this flag table
          -l            little version
          -s            chuff and whistle
          -v            print version
          -w            windy: moves faster
          -<n>          pull n trailing cars (1-10)
          --cars N      pull N cars (0-50; 0 = locomotive only)
          --all         traverse every connected display
          --model FILE  load a .usdz/.scn/.dae locomotive (default: bundled)
          --freeze SEC  render one frozen frame and hold
          --duration SEC  cap the run at SEC seconds
          --scale F     train size multiplier (default 1)
          --angle DEG   camera azimuth: 0 = flat side view (default 55)
          --color V     livery respray: color name or hue degrees (default: black; 'factory' restores as-built)
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
            guard (1...10).contains(n) else {
                return .invalidCarCount(n, expected: "1-10")
            }
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
                case "model", "freeze", "duration", "scale", "cars",
                     "angle", "color":
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
                    } else if name == "scale" {
                        guard let factor = Double(value),
                              factor.isFinite, factor > 0 else {
                            return .failure(.invalidValue("--scale", value))
                        }
                        spec.scale = factor
                    } else if name == "duration" {
                        guard let seconds = Double(value),
                              seconds.isFinite, seconds > 0 else {
                            return .failure(.invalidValue("--duration", value))
                        }
                        spec.duration = seconds
                    } else if name == "cars" {
                        guard let n = Int(value) else {
                            return .failure(.invalidValue("--cars", value))
                        }
                        guard (0...50).contains(n) else {
                            return .failure(.invalidCarCount(n,
                                                           expected: "0-50"))
                        }
                        spec.cars = n
                    } else if name == "angle" {
                        guard let degrees = Double(value),
                              degrees.isFinite,
                              (0...75).contains(degrees) else {
                            return .failure(.invalidValue("--angle", value))
                        }
                        spec.viewAngle = degrees
                    } else if name == "color" {
                        if ["factory", "none"].contains(value.lowercased()) {
                            spec.livery = nil
                        } else if let named = Livery.named[value.lowercased()] {
                            spec.livery = named
                        } else if let degrees = Double(value),
                                  degrees.isFinite,
                                  (0..<360).contains(degrees) {
                            spec.livery = Livery(hue: degrees / 360)
                        } else {
                            return .failure(.invalidValue("--color", value))
                        }
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
                case "d": spec.disco = true
                case "e": spec.allowInterrupt = true
                case "F": spec.fly = true
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
