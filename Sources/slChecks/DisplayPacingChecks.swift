import SLCore
import SLTestKit

public let displayPacingChecks: [Check] = [
    Check("when a display link is available pacing prefers the display link") {
        try expectEqual(
            FramePacing.source(displayLinkAvailable: true), .displayLink)
    },
    Check("when no display link can be created pacing falls back to the timer") {
        try expectEqual(
            FramePacing.source(displayLinkAvailable: false), .timer)
    },
    Check("when the timer paces frames its cadence stays at 120 Hz") {
        try expectEqual(FramePacing.fallbackInterval, 1.0 / 120)
    },
    Check("when the timer cadence is asked for its bounds it is positive and finite") {
        try expect(FramePacing.fallbackInterval > 0)
        try expect(FramePacing.fallbackInterval.isFinite)
    },
]
