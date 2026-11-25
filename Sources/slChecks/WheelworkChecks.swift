import SceneKit
import SLCore
import SLTestKit
import TrainScene

private func find(_ name: String, in node: SCNNode) -> SCNNode? {
    node.childNode(withName: name, recursively: true)
}

/// Rolling radius of a `wheel-*` pivot, read off its cylinder mesh —
/// the same source `WheelworkAnimator` uses.
private func wheelRadius(_ wheel: SCNNode) -> CGFloat {
    wheel.childNodes.lazy
        .compactMap { $0.geometry as? SCNCylinder }
        .first?.radius ?? 0
}

private func wheelAngle(_ name: String, in loco: SCNNode) -> CGFloat {
    find(name, in: loco)?.eulerAngles.z ?? .nan
}

public let wheelworkChecks: [Check] = [
    Check("when the animator advances one circumference the driver wheel has turned one full turn") {
        try MainActor.assumeIsolated {
            let loco = ProceduralLocomotive().node
            let animator = WheelworkAnimator(train: loco)
            let driver = find("wheel-driver-1", in: loco)!
            let radius = wheelRadius(driver)
            animator.update(distance: 2 * CGFloat.pi * radius)
            let angle = driver.eulerAngles.z
            try expect(abs(angle - 2 * CGFloat.pi) < 0.001,
                       "angle \(angle), want \(2 * CGFloat.pi)")
        }
    },
    Check("when the same distance advances wheels of different radii they turn through different angles") {
        try MainActor.assumeIsolated {
            let loco = ProceduralLocomotive().node
            let animator = WheelworkAnimator(train: loco)
            animator.update(distance: 100)
            let leading = wheelAngle("wheel-leading", in: loco)
            let driver = wheelAngle("wheel-driver-1", in: loco)
            try expect(leading != driver,
                       "leading \(leading) == driver \(driver)")
            // Smaller wheel → larger angle for the same distance.
            try expect(leading > driver,
                       "leading \(leading) not > driver \(driver)")
        }
    },
    Check("when distance grows the connecting rods reciprocate vertically and return to rest") {
        try MainActor.assumeIsolated {
            let loco = ProceduralLocomotive().node
            let animator = WheelworkAnimator(train: loco)
            let rod = find("rod-drive", in: loco)!
            let restY = rod.position.y
            let driverRadius = wheelRadius(find("wheel-driver-1", in: loco)!)
            // Quarter crank turn: pin is at max offset.
            animator.update(distance: CGFloat.pi / 2 * driverRadius)
            let upY = rod.position.y
            try expect(abs(upY - restY) > 1,
                       "rod did not move: \(upY) vs rest \(restY)")
            // Half turn: pin back at axle height.
            animator.update(distance: CGFloat.pi * driverRadius)
            try expect(abs(rod.position.y - restY) < 0.01,
                       "rod not back at rest: \(rod.position.y)")
        }
    },
    Check("when the SceneKit renderer renders at two times the wheel angles differ") {
        try MainActor.assumeIsolated {
            let spec = RunSpec.parse(["sl"])
            guard case .success(let runSpec) = spec else {
                try expect(false, "default spec must parse")
                return
            }
            let renderer = SceneKitRenderer(spec: runSpec, stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: runSpec) as? SCNView,
                  let scene = view.scene,
                  let loco = scene.rootNode.childNode(
                    withName: "procedural-locomotive", recursively: true) else {
                try expect(false, "no locomotive in scene")
                return
            }
            renderer.render(at: 1.0)
            let t1 = wheelAngle("wheel-driver-1", in: loco)
            renderer.render(at: 3.0)
            let t3 = wheelAngle("wheel-driver-1", in: loco)
            try expect(t1 != t3,
                       "wheel angle frozen: \(t1) at both t=1 and t=3")
        }
    },
    Check("when -w is passed the crossing is shorter so the wheels spin faster") {
        try MainActor.assumeIsolated {
            guard case .success(let windy) = RunSpec.parse(["sl", "-w"]),
                  case .success(let calm) = RunSpec.parse(["sl"]) else {
                try expect(false, "specs must parse")
                return
            }
            let fast = SceneKitRenderer(spec: windy, stripWidth: 1000)
            let slow = SceneKitRenderer(spec: calm, stripWidth: 1000)
            try expect(fast.duration < slow.duration,
                       "-w duration \(fast.duration) !< \(slow.duration)")
        }
    },
    Check("when the train node has no wheel hooks the animator update does nothing") {
        MainActor.assumeIsolated {
            let animator = WheelworkAnimator(train: SCNNode())
            animator.update(distance: 500)
        }
    },
]
