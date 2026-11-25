import Foundation

/// Single source for the version string; `VERSION` at the repo root is
/// bumped by releases and mirrored here by the release task.
public enum SLVersion {
    public static let current = "0.1.0"
}
