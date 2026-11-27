import Foundation
import SLTestKit

// Hidden evidence modes for `scripts/shot` — not part of the check
// suite; they exit before CheckRunner ever sees them.
let cli = Array(CommandLine.arguments.dropFirst())
if let command = cli.first {
    switch command {
    case "shot-lane":
        exit(ShotEvidence.laneCommand(Array(cli.dropFirst())))
    case "shot-verify":
        exit(ShotEvidence.verifyCommand(Array(cli.dropFirst())))
    case "shot-render":
        exit(ShotEvidence.renderCommand(Array(cli.dropFirst())))
    default:
        break
    }
}

let failures = CheckRunner.run(Registry.all)
// Probe: if CI dies after this line, the crash is in process
// teardown (static destructors / SceneKit globals), not a check.
FileHandle.standardError.write(
    Data("slChecks: suite complete, \(failures) failed\n".utf8))
fflush(stdout)
exit(failures == 0 ? 0 : 1)
