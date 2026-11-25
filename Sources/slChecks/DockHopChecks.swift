import AppKit
import OverlayKit
import SLCore
import SLTestKit
import TrainScene

private let zone = DockZone(minX: 400, maxX: 700)
private let hopped = Trajectory(
    laneWidth: 1000, trainWidth: 200, trainHeight: 80,
    margin: 10, duration: 8, dock: [zone]
)
private let plain = Trajectory(
    laneWidth: 1000, trainWidth: 200, trainHeight: 80,
    margin: 10, duration: 8
)
private let flying = Trajectory(
    laneWidth: 1000, trainWidth: 200, trainHeight: 80,
    margin: 10, duration: 8, fly: true, dock: [zone]
)

/// Seconds since train-enter at which the train center sits at `x`
/// (the trajectory's x(t) is linear).
private func t(forX x: Double, in tr: Trajectory) -> TimeInterval {
    let start = tr.laneWidth + tr.margin + tr.trainWidth / 2
    let end = -(tr.margin + tr.trainWidth / 2)
    return tr.duration * (start - x) / (start - end)
}

public let dockHopChecks: [Check] = [
    Check("when the lane has no dock zone the pose holds the lane height across the run") {
        for t in stride(from: 1.0, through: 7.0, by: 1.5) {
            let pose = plain.pose(at: t)
            try expectEqual(pose.y, 50)
            try expectEqual(pose.heading, 0)
        }
    },
    Check("when the train crosses a dock zone its pose lifts above the lane and lands back") {
        let before = hopped.pose(at: t(forX: 800, in: hopped))
        let mid = hopped.pose(at: t(forX: 550, in: hopped))
        let after = hopped.pose(at: t(forX: 300, in: hopped))
        try expectEqual(before.y, 50)
        try expect(mid.y > 50, "mid-hop y \(mid.y) not above lane")
        try expectEqual(after.y, 50)
    },
    Check("when the train is at the dock zone center its pose peaks at the apex") {
        let pose = hopped.pose(at: t(forX: 550, in: hopped))
        try expect(abs(pose.y - 90) < 1e-9, "peak y \(pose.y) != 90")
        try expect(abs(pose.heading) < 1e-9, "peak heading \(pose.heading) != 0")
    },
    Check("when the train enters a dock zone it pitches nose-up") {
        let pose = hopped.pose(at: t(forX: 680, in: hopped))
        try expect(pose.heading < 0, "entry heading \(pose.heading) not nose-up")
        try expect(pose.y > 50, "entry y \(pose.y) not lifted")
    },
    Check("when the train leaves a dock zone it pitches nose-down") {
        let pose = hopped.pose(at: t(forX: 420, in: hopped))
        try expect(pose.heading > 0, "exit heading \(pose.heading) not nose-down")
        try expect(pose.y > 50, "exit y \(pose.y) not lifted")
    },
    Check("when flying over a dock zone the hop does not apply") {
        let pose = flying.pose(at: t(forX: 550, in: flying))
        try expectEqual(pose.y, (1000 - pose.x) / 7 + 40)
        try expectEqual(pose.heading, -atan(1.0 / 7.0))
    },
    Check("when a screen's visible frame sits above its frame a dock zone is reported in lane coordinates") {
        let zones = OverlayGeometry.dockZones(
            screenFrames: [NSRect(x: 0, y: 0, width: 1512, height: 982)],
            visibleFrames: [NSRect(x: 0, y: 80, width: 1512, height: 902)],
            lane: NSRect(x: 0, y: 0, width: 1512, height: 180))
        try expectEqual(zones.count, 1)
        let z = zones[0]
        try expectEqual(z.minX, 456)
        try expectEqual(z.maxX, 1056)
        try expectEqual(z.apex, 40)
        try expect(z.contains(756))
        try expect(!z.contains(100))
    },
    Check("when the visible frame matches the frame no dock zone is reported") {
        let frame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let zones = OverlayGeometry.dockZones(
            screenFrames: [frame], visibleFrames: [frame],
            lane: NSRect(x: 0, y: 0, width: 1512, height: 180))
        try expect(zones.isEmpty)
    },
    Check("when only a side edge insets the visible frame no dock zone is reported") {
        let zones = OverlayGeometry.dockZones(
            screenFrames: [NSRect(x: 0, y: 0, width: 1512, height: 982)],
            visibleFrames: [NSRect(x: 80, y: 0, width: 1432, height: 982)],
            lane: NSRect(x: 0, y: 0, width: 1512, height: 180))
        try expect(zones.isEmpty)
    },
]
