import SLCore
import SLTestKit

/// Unwraps a successful parse or fails the check with the parse error.
private func spec(_ args: [String]) throws -> RunSpec {
    switch RunSpec.parse(args) {
    case .success(let spec): return spec
    case .failure(let error):
        try expect(false, "parse failed: \(error.message)")
        fatalError("unreachable: expect(false) always throws")
    }
}

/// Parses `args` and asserts one Bool field — spec-sentence shorthand.
private func expectFlag(_ args: [String], _ field: KeyPath<RunSpec, Bool>) throws {
    let value = try spec(args)[keyPath: field]
    try expect(value, "\(args) did not set \(field)")
}

private func parseFails(_ args: [String]) throws {
    if case .success = RunSpec.parse(args) {
        try expect(false, "expected parse failure for \(args)")
    }
}

public let runSpecChecks: [Check] = [
    Check("when invoked with no arguments it returns the default spec") {
        let s = try spec(["sl"])
        try expect(!s.accident && !s.disco && !s.allowInterrupt)
        try expect(!s.fly && !s.little && !s.sound)
        try expectEqual(s.cars, 1)
        try expectEqual(s.speedFactor, 1.0)
        try expect(s.model == nil && !s.allDisplays && s.freeze == nil && !s.stealth)
        try expect(!s.versionRequested && !s.helpRequested)
    },
    Check("when invoked with -a it requests the accident") {
        try expectFlag(["sl", "-a"], \.accident)
    },
    Check("when invoked with -c it reports a parse error") {
        try parseFails(["sl", "-c"])
    },
    Check("when invoked with -d it requests disco mode") {
        try expectFlag(["sl", "-d"], \.disco)
    },
    Check("when invoked with -e it allows interruption") {
        try expectFlag(["sl", "-e"], \.allowInterrupt)
    },
    Check("when invoked with -F it requests flight") {
        try expectFlag(["sl", "-F"], \.fly)
    },
    Check("when invoked with -G it reports a parse error") {
        try parseFails(["sl", "-G"])
    },
    Check("when invoked with -l it requests the little train") {
        try expectFlag(["sl", "-l"], \.little)
    },
    Check("when invoked with -s it requests sound") {
        try expectFlag(["sl", "-s"], \.sound)
    },
    Check("when invoked with -w it raises the speed factor") {
        let s = try spec(["sl", "-w"])
        try expect(s.speedFactor > 1.0)
    },
    Check("when invoked with -v it requests the version") {
        try expectFlag(["sl", "-v"], \.versionRequested)
    },
    Check("when invoked with -h it requests help") {
        try expectFlag(["sl", "-h"], \.helpRequested)
    },
    Check("when invoked with --version it requests the version") {
        try expectFlag(["sl", "--version"], \.versionRequested)
    },
    Check("when invoked with --help it requests help") {
        try expectFlag(["sl", "--help"], \.helpRequested)
    },
    Check("when invoked with a clustered short group it sets every flag") {
        let s = try spec(["sl", "-alF"])
        try expect(s.accident && s.little && s.fly)
        try expect(!s.disco)
    },
    Check("when invoked with -3 it pulls three cars") {
        let s = try spec(["sl", "-3"])
        try expectEqual(s.cars, 3)
    },
    Check("when invoked with -10 it pulls ten cars") {
        let s = try spec(["sl", "-10"])
        try expectEqual(s.cars, 10)
    },
    Check("when invoked with -0 it reports a parse error") {
        try parseFails(["sl", "-0"])
    },
    Check("when invoked with -11 it reports a parse error") {
        try parseFails(["sl", "-11"])
    },
    Check("when invoked with --cars and a count it pulls that many cars") {
        let s = try spec(["sl", "--cars", "7"])
        try expectEqual(s.cars, 7)
    },
    Check("when invoked with --cars=0 it runs the locomotive light") {
        let s = try spec(["sl", "--cars=0"])
        try expectEqual(s.cars, 0)
    },
    Check("when invoked with --cars and a non-number it reports a parse error") {
        try parseFails(["sl", "--cars", "many"])
    },
    Check("when invoked with --cars beyond fifty it reports a parse error") {
        try parseFails(["sl", "--cars", "51"])
    },
    Check("when invoked with --cars and no value it reports a parse error") {
        try parseFails(["sl", "--cars"])
    },
    Check("when invoked with --all it traverses every display") {
        try expectFlag(["sl", "--all"], \.allDisplays)
    },
    Check("when invoked with --model and a file it records the model") {
        let s = try spec(["sl", "--model", "engine.usdz"])
        try expectEqual(s.model, "engine.usdz")
    },
    Check("when invoked with --model=file it records the model") {
        let s = try spec(["sl", "--model=train.scn"])
        try expectEqual(s.model, "train.scn")
    },
    Check("when invoked with --freeze and seconds it records the freeze") {
        let s = try spec(["sl", "--freeze", "2.5"])
        try expectEqual(s.freeze, 2.5)
    },
    Check("when invoked with --freeze=seconds it records the freeze") {
        let s = try spec(["sl", "--freeze=1.25"])
        try expectEqual(s.freeze, 1.25)
    },
    Check("when invoked with --stealth it requests stealth") {
        try expectFlag(["sl", "--stealth"], \.stealth)
    },
    Check("when invoked with --model and no value it reports a parse error") {
        try parseFails(["sl", "--model"])
    },
    Check("when invoked with --freeze and a non-number it reports a parse error") {
        try parseFails(["sl", "--freeze", "soon"])
    },
    Check("when invoked with an unknown short flag it reports a parse error") {
        try parseFails(["sl", "-z"])
    },
    Check("when invoked with an unknown long flag it reports a parse error") {
        try parseFails(["sl", "--bogus"])
    },
    Check("when invoked with a bare argument it reports a parse error") {
        try parseFails(["sl", "railway"])
    },
    Check("when invoked with -3a it applies the car count then the flag") {
        let s = try spec(["sl", "-3a"])
        try expectEqual(s.cars, 3)
        try expect(s.accident)
    },
    Check("when invoked with --model= and an empty value it reports a parse error") {
        try parseFails(["sl", "--model="])
    },
    Check("when asked for the usage it prints the whole flag table") {
        let text = RunSpec.usage()
        for flag in ["-a", "-d", "-e", "-F", "-l", "-s", "-v", "-w",
                     "-<n>", "--cars", "--all", "--model", "--freeze",
                     "--angle", "--stealth"] {
            try expect(text.contains(flag), "usage() lacks \(flag)")
        }
    },
    Check("when invoked with --angle it records the camera azimuth within bounds") {
        try expectEqual(try spec(["sl"]).viewAngle, 55)
        try expectEqual(try spec(["sl", "--angle", "40"]).viewAngle, 40)
        try expectEqual(try spec(["sl", "--angle=0"]).viewAngle, 0)
        try parseFails(["sl", "--angle", "-5"])
        try parseFails(["sl", "--angle", "90"])
        try parseFails(["sl", "--angle", "flat"])
        try parseFails(["sl", "--angle"])
    },
    Check("when a parse fails the error describes the cause") {
        let cases: [(args: [String], needle: String)] = [
            (["sl", "-z"], "unknown flag"),
            (["sl", "railway"], "unexpected argument"),
            (["sl", "--model"], "requires a value"),
            (["sl", "--freeze", "soon"], "invalid value"),
            (["sl", "--cars", "many"], "invalid value"),
            (["sl", "-0"], "invalid car count"),
        ]
        for (args, needle) in cases {
            guard case .failure(let error) = RunSpec.parse(args) else {
                try expect(false, "expected parse failure for \(args)")
                continue
            }
            try expect(error.message.contains(needle),
                       "\(args) error '\(error.message)' lacks '\(needle)'")
            try expectEqual(error.description, error.message)
        }
    },
]

public let slVersionChecks: [Check] = [
    Check("when asked for the version it returns a semver string") {
        let parts = SLVersion.current.split(separator: ".")
        try expectEqual(parts.count, 3)
        try expect(parts.allSatisfy { $0.allSatisfy(\.isNumber) })
    },
]
