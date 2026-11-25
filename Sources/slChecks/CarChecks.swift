import SceneKit
import SLCore
import SLTestKit
import TrainScene

private func find(_ name: String, in node: SCNNode) -> SCNNode? {
    node.childNode(withName: name, recursively: true)
}

private func spec(_ args: [String]) -> RunSpec {
    switch RunSpec.parse(args) {
    case .success(let s): return s
    case .failure(let e): fatalError("spec must parse: \(e)")
    }
}

/// The `car-chain` node inside a rendered scene's train subtree.
@MainActor
private func carChain(in scene: SCNScene) -> SCNNode? {
    scene.rootNode.childNode(withName: "car-chain", recursively: true)
}

@MainActor
private func scene(for args: [String]) -> SCNScene? {
    let runSpec = spec(args)
    let renderer = SceneKitRenderer(spec: runSpec, stripWidth: 1000)
    guard let view = renderer.makeView(
        in: NSRect(x: 0, y: 0, width: 1000, height: 180),
        spec: runSpec) as? SCNView else { return nil }
    return view.scene
}

public let carChecks: [Check] = [
    Check("when asked for three cars the chain returns three car nodes in coupling order") {
        let chain = Car.cars(n: 3)
        try expect(chain.childNodes.count == 3,
                   "found \(chain.childNodes.count) cars")
        let names = chain.childNodes.map { $0.name ?? "" }
        for i in 1...3 {
            try expect(names.contains("car-\(i)"), "missing car-\(i)")
        }
        // Coupling order: car-1 nearest the loco (smallest x), even pitch.
        let xs = chain.childNodes.map(\.position.x)
        try expect(xs[0] < xs[1] && xs[1] < xs[2],
                   "cars not ordered rearward: \(xs)")
        try expect(abs((xs[1] - xs[0]) - (xs[2] - xs[1])) < 0.001,
                   "uneven car pitch: \(xs)")
    },
    Check("when asked for zero cars the chain is empty") {
        try expect(Car.cars(n: 0).childNodes.isEmpty)
        try expect(Car.chainLength(n: 0) == 0)
    },
    Check("when a car is built its pivot sits at track contact centered on x") {
        let b = Car().node.boundingBox
        try expect(abs(b.min.y) < 0.5, "min.y = \(b.min.y)")
        try expect(abs(b.min.x + b.max.x) < 1,
                   "not centered: \(b.min.x)…\(b.max.x)")
        try expect(b.max.x - b.min.x > 150,
                   "width = \(b.max.x - b.min.x)")
    },
    Check("when cars couple the chain length grows with the car count") {
        try expect(Car.chainLength(n: 3) > Car.chainLength(n: 1))
        try expect(Car.chainLength(n: 1)
                   == Car.size.width + Car.couplingGap)
    },
    Check("when the spec asks for -3 the rendered scene holds three cars behind the loco") {
        try MainActor.assumeIsolated {
            guard let scene = scene(for: ["sl", "-3"]),
                  let chain = carChain(in: scene) else {
                try expect(false, "no car chain in scene")
                return
            }
            try expect(chain.childNodes.count == 3,
                       "found \(chain.childNodes.count) cars")
            // The chain's origin sits on the loco's rear edge (+x
            // side). `boundingBox` covers the whole subtree, so the
            // standalone locomotive gives the un-coupled rear edge.
            let loneRear = ProceduralLocomotive().node.boundingBox.max.x
            try expect(chain.position.x > 0,
                       "chain at x=\(chain.position.x), want > 0")
            try expect(abs(chain.position.x - loneRear) < 1,
                       "chain x=\(chain.position.x) vs loco rear \(loneRear)")
            // car-1 is nearest the loco.
            let first = chain.childNode(withName: "car-1", recursively: false)
            let last = chain.childNode(withName: "car-3", recursively: false)
            try expect(first != nil && last != nil)
            if let first, let last {
                try expect(first.position.x < last.position.x,
                           "car-1 not nearest the loco")
            }
        }
    },
    Check("when the spec asks for -3 each car rides at track contact behind the previous") {
        try MainActor.assumeIsolated {
            guard let scene = scene(for: ["sl", "-3"]),
                  let chain = carChain(in: scene) else {
                try expect(false, "no car chain in scene")
                return
            }
            // Every car pivot is track-contact in its own local space
            // and the chain sits at the loco's bottom (y = 0), so all
            // car bottoms share one rail line.
            for car in chain.childNodes {
                let b = car.boundingBox
                try expect(abs(b.min.y) < 1.0,
                           "car \(car.name ?? "?") floats: min.y=\(b.min.y)")
            }
        }
    },
    Check("when rendered mid-run the snapshot shows the loco and three cars as separated clusters") {
        try MainActor.assumeIsolated {
            let runSpec = spec(["sl", "-3"])
            let renderer = SceneKitRenderer(spec: runSpec, stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: runSpec) as? SCNView else {
                try expect(false, "view is not an SCNView")
                return
            }
            // t = 4 centers the ~982pt consist on the 1000pt lane.
            renderer.render(at: 4)
            let image = view.snapshot()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else {
                try expect(false, "SCNView produced no snapshot")
                return
            }
            // Lit columns: `snapshot()` fills the clear scene with
            // white, so a column counts when it holds a non-white
            // (train) pixel. Cars are separated by real gaps, so lit
            // columns cluster per vehicle.
            var lit = [Bool](repeating: false, count: rep.pixelsWide)
            for x in 0..<rep.pixelsWide {
                for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                    guard let c = rep.colorAt(x: x, y: y),
                          c.alphaComponent > 0.5 else { continue }
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                    c.getRed(&r, green: &g, blue: &b, alpha: nil)
                    if r + g + b < 2.7 {
                        lit[x] = true
                        break
                    }
                }
            }
            var clusters: [(Int, Int)] = []
            var x = 0
            while x < rep.pixelsWide {
                guard lit[x] else { x += 1; continue }
                var end = x
                // Merge across sub-4px anti-aliased dropouts inside
                // one vehicle; real coupling gaps are wider.
                while end + 1 < rep.pixelsWide {
                    var look = end + 1
                    var gap = 0
                    while look < rep.pixelsWide && !lit[look] && gap < 4 {
                        look += 1; gap += 1
                    }
                    guard look < rep.pixelsWide, lit[look] else { break }
                    end = look
                }
                clusters.append((x, end))
                x = end + 1
            }
            try expect(clusters.count == 4,
                       "expected loco + 3 car clusters, got \(clusters)")
        }
    },
    Check("when the animator advances distance the car wheels turn with the consist") {
        try MainActor.assumeIsolated {
            guard let scene = scene(for: ["sl", "-3"]),
                  let loco = find("procedural-locomotive",
                                  in: scene.rootNode),
                  let wheel = find("wheel-car-1", in: loco) else {
                try expect(false, "no car wheel in scene")
                return
            }
            let animator = WheelworkAnimator(train: loco)
            animator.update(distance: 100)
            let turned = abs(wheel.eulerAngles.z) > 0.001
            try expect(turned,
                       "car wheel did not turn: \(wheel.eulerAngles.z)")
        }
    },
]
