import SLCore
import SLTestKit

/// Marker for code after `expect(false)` — unreachable because expect
/// always throws, but the compiler can't see that.
private struct Unreachable: Error {}

/// Unwraps a successful parse or fails the check — the failure branch
/// is itself covered by "when the spec helper meets a bad parse it
/// throws".
private func spec(_ args: [String]) throws -> RunSpec {
    guard case .success(let s) = RunSpec.parse(args) else {
        try expect(false, "parse failed: \(args)")
        throw Unreachable()
    }
    return s
}

/// Asserts `RunSpec.parse` rejects `args`; the failure branch is
/// covered by "when the parseFails helper meets a good parse it
/// throws".
private func parseFails(_ args: [String]) throws {
    guard case .failure = RunSpec.parse(args) else {
        try expect(false, "expected parse failure for \(args)")
        throw Unreachable()
    }
}

public let runLoopChecks: [Check] = [
    Check("when a run finishes naturally it exits with status zero") {
        try expectEqual(ExitReason.finished.exitCode, 0)
    },
    Check("when no display is attached it exits with status one") {
        try expectEqual(ExitReason.noDisplay.exitCode, 1)
    },
    Check("when the watchdog fires it exits nonzero and distinct from a natural finish") {
        try expect(ExitReason.watchdog.exitCode != 0)
        try expect(ExitReason.watchdog.exitCode != ExitReason.finished.exitCode)
    },
    Check("when interrupted with -e it exits with about 130") {
        try expectEqual(ExitReason.interrupted.exitCode, 130)
    },
    Check("when every exit reason is asked for its code the codes are distinct") {
        let codes = [ExitReason.finished, .noDisplay, .watchdog, .interrupted]
            .map(\.exitCode)
        try expectEqual(Set(codes).count, codes.count)
    },
    Check("when invoked with --duration it records the run cap") {
        let s = try spec(["sl", "--duration", "4.5"])
        try expectEqual(s.duration, 4.5)
    },
    Check("when invoked with --duration=seconds it records the run cap") {
        let s = try spec(["sl", "--duration=2"])
        try expectEqual(s.duration, 2)
    },
    Check("when invoked without --duration the run cap is unset") {
        let s = try spec(["sl"])
        try expect(s.duration == nil)
    },
    Check("when invoked with --duration and a non-number it reports a parse error") {
        try parseFails(["sl", "--duration", "soon"])
    },
    Check("when invoked with --duration and a non-positive value it reports a parse error") {
        try parseFails(["sl", "--duration", "0"])
        try parseFails(["sl", "--duration=-3"])
    },
    Check("when the spec helper meets a bad parse it throws") {
        var threw = false
        do {
            _ = try spec(["sl", "--bogus"])
        } catch is CheckFailure {
            threw = true
        }
        try expect(threw, "spec() should have thrown")
    },
    Check("when the parseFails helper meets a good parse it throws") {
        var threw = false
        do {
            try parseFails(["sl"])
        } catch is CheckFailure {
            threw = true
        }
        try expect(threw, "parseFails() should have thrown")
    },
]
