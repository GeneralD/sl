import Foundation

/// Frame pacing policy for the run loop: the display's own refresh
/// (CVDisplayLink) is preferred — vsync-locked and ProMotion-aware —
/// with a fixed-cadence Timer as the fallback when no display link can
/// be created.
public enum FramePacing {
    /// Which mechanism drives `onFrame`.
    public enum Source: Sendable, Equatable {
        case displayLink
        case timer
    }

    /// Timer cadence when no display link exists. Matches the panel's
    /// high-refresh ceiling so the fallback never exceeds what the
    /// display can show.
    public static let fallbackInterval: TimeInterval = 1.0 / 120

    /// The pacing source for a run: display link whenever the system
    /// can vend one, timer otherwise.
    public static func source(displayLinkAvailable: Bool) -> Source {
        displayLinkAvailable ? .displayLink : .timer
    }
}
