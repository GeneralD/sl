import AppKit
import SLTestKit
import TrainScene

private let lane = Trajectory(
    laneWidth: 1000, trainWidth: 200, trainHeight: 80,
    margin: 10, duration: 4
)

public let trajectoryChecks: [Check] = [
    Check("when asked at the start it returns a pose fully off-screen right") {
        let pose = lane.pose(at: 0)
        try expect(pose.x - 100 > 1000, "start x \(pose.x) not past right edge")
        try expect(!pose.finished)
    },
    Check("when asked at the end of the duration it returns a finished pose off-screen left") {
        let pose = lane.pose(at: lane.duration)
        try expect(pose.finished)
        try expect(pose.x + 100 <= -10, "end x \(pose.x) not past left edge")
    },
    Check("when asked partway through it returns an x between the edges that decreases with t") {
        let early = lane.pose(at: lane.duration * 0.25)
        let late = lane.pose(at: lane.duration * 0.75)
        try expect(early.x > late.x, "x not decreasing: \(early.x) -> \(late.x)")
        try expect(late.x < 1000 && late.x > -110)
    },
    Check("when asked for a pose it carries x, y, heading, and finished") {
        let pose = lane.pose(at: lane.duration * 0.5)
        try expectEqual(pose.heading, 0)
        try expectEqual(pose.y, 50)
        try expect(!pose.finished)
    },
    Check("when the presenter updates past the duration it reports finished") {
        try MainActor.assumeIsolated {
            let node = NSView(frame: .zero)
            let presenter = TrainPresenter(trajectory: lane, node: node)
            presenter.update(t: lane.duration + 1)
            try expect(presenter.finished)
            try expect(node.frame.maxX <= -10, "node still on screen: \(node.frame)")
        }
    },
]
