import SLTestKit

/// Every feature appends its check list here — one line per feature file.
/// `merge=union` in .gitattributes keeps concurrent appends conflict-free.
public enum Registry {
    public static let all: [Check] =
        runSpecChecks
        + slVersionChecks
        + manPageChecks
        + audioAssetChecks
        + audioEngineChecks
        + sceneKitChecks
        + locomotiveChecks
        + trajectoryChecks
        + flightChecks
        + allDisplayChecks
        + runLoopChecks
        + discoChecks
        + hardeningChecks
        + modelAssetChecks
        + screamerChecks
        + wheelworkChecks
        + dockHopChecks
}
