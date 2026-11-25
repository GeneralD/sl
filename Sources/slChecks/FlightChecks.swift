import AppKit
import SLCore
import SLTestKit
import TrainScene

private let laneHeight = 180.0
private let flight = Trajectory(
    laneWidth: 1000, trainWidth: 200, trainHeight: 80,
    margin: 10, duration: 4, fly: true
)

public let flightChecks: [Check] = [
    Check("when invoked with -F it requests flight") {
        try expect(RunSpec.parse(["sl", "-F"]).fly)
        try expect(!RunSpec.parse(["sl"]).fly)
    },
    Check("when -F is combined with --freeze both apply") {
        let spec = RunSpec.parse(["sl", "--freeze", "2", "-F"])
        try expect(spec.fly)
        try expect(spec.freezeAt == 2)
        try expect(spec.parseError == nil)
    },
    Check("when flying the climb slope is 1/7") {
        let early = flight.pose(at: 0.5)
        let late = flight.pose(at: 1.5)
        try expect(late.x < early.x, "x not decreasing: \(early.x) -> \(late.x)")
        try expect(late.y > early.y, "y not climbing: \(early.y) -> \(late.y)")
        let slope = (late.y - early.y) / (early.x - late.x)
        try expect(abs(slope - 1.0 / 7.0) < 1e-9, "slope \(slope) != 1/7")
    },
    Check("when asked at the end of a flight it returns a pose beyond the upper-left corner") {
        let pose = flight.pose(at: flight.duration)
        try expect(pose.finished)
        try expect(pose.x + 100 <= -10, "end x \(pose.x) not past left edge")
        try expect(pose.y > laneHeight,
                   "end y \(pose.y) not above lane top \(laneHeight)")
    },
    Check("when flying it tilts the heading nose-up by atan(1/7)") {
        let pose = flight.pose(at: flight.duration * 0.5)
        try expect(abs(pose.heading - (-atan(1.0 / 7.0))) < 1e-12,
                   "heading \(pose.heading)")
    },
    Check("when the presenter updates a flying pose it tilts the node to the heading") {
        try MainActor.assumeIsolated {
            let node = NSView(frame: .zero)
            let presenter = TrainPresenter(trajectory: flight, node: node)
            presenter.update(t: flight.duration * 0.5)
            let tilt = -atan(1.0 / 7.0) * 180 / .pi
            try expect(abs(node.boundsRotation - tilt) < 1e-9,
                       "boundsRotation \(node.boundsRotation) != \(tilt)")
            try expect(!presenter.finished)
        }
    },
]
