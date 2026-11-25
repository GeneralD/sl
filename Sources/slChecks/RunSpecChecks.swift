import SLCore
import SLTestKit

public let runSpecChecks: [Check] = [
    Check("when invoked with -v it requests the version") {
        try expect(RunSpec.parse(["sl", "-v"]).versionRequested)
    },
    Check("when invoked with --version it requests the version") {
        try expect(RunSpec.parse(["sl", "--version"]).versionRequested)
    },
    Check("when invoked with --help it requests help") {
        try expect(RunSpec.parse(["sl", "--help"]).helpRequested)
    },
    Check("when invoked with an unknown flag it reports a parse error") {
        let spec = RunSpec.parse(["sl", "--bogus"])
        try expect(spec.parseError != nil)
    },
]

public let slVersionChecks: [Check] = [
    Check("when asked for the version it returns a semver string") {
        let parts = SLVersion.current.split(separator: ".")
        try expectEqual(parts.count, 3)
        try expect(parts.allSatisfy { $0.allSatisfy(\.isNumber) })
    },
]
