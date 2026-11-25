import SceneKit
import SLCore
import SLTestKit
import TrainScene

private func spec(_ args: [String]) -> RunSpec {
    switch RunSpec.parse(args) {
    case .success(let s): return s
    case .failure(let e): fatalError("spec must parse: \(e)")
    }
}

/// SceneKitRenderer keeps no scene reference, so render first and
/// read the view's scene back.
@MainActor
private func renderedScene(for args: [String],
                           at t: TimeInterval = 0) -> SCNScene? {
    let runSpec = spec(args)
    let renderer = SceneKitRenderer(spec: runSpec, stripWidth: 1000)
    let view = renderer.makeView(
        in: NSRect(x: 0, y: 0, width: 1000, height: 180),
        spec: runSpec) as? SCNView
    renderer.render(at: t)
    return view?.scene
}

@MainActor
private func chain(in scene: SCNScene?) -> SCNNode? {
    scene?.rootNode.childNode(withName: "car-chain", recursively: true)
}

/// A real .scn fixture the injectable `resolve` seam can serve as
/// any asset name; caller removes the directory.
@MainActor
private func writeSCNFixture(
    _ name: String = "car.scn", height: CGFloat = 20
) throws -> URL {
    let scene = SCNScene()
    scene.rootNode.addChildNode(SCNNode(geometry: SCNBox(
        width: 10, height: height, length: 5, chamferRadius: 0)))
    let data = try NSKeyedArchiver.archivedData(
        withRootObject: scene, requiringSecureCoding: false)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("sl-consist-\(UUID().uuidString)",
                                isDirectory: true)
    try FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent(name))
    return dir
}

public let modelConsistChecks: [Check] = [
    Check("when three cars are requested the consist names a tender then two coaches") {
        try expectEqual(ModelConsist.assetNames(carCount: 3),
                        ["tender.usdz", "coach.usdz", "coach.usdz"])
        try expectEqual(ModelConsist.assetNames(carCount: 1),
                        ["tender.usdz"])
        try expect(ModelConsist.assetNames(carCount: 0).isEmpty,
                   "zero cars should name no assets")
    },
    Check("when the bundled consist loads every car keeps real-world height proportion to the loco") {
        try MainActor.assumeIsolated {
            let cars = ModelConsist.load(carCount: 3)
            try expectEqual(cars?.count, 3)
            let locoH = ProceduralLocomotive.size.height
            // tender.usdz is 3.5m vs loco 4.2m; coach 4.3m — heights
            // must land near those ratios, not all equal.
            let tenderRatio = (cars?[0].size.height ?? 0) / locoH
            let coachRatio = (cars?[1].size.height ?? 0) / locoH
            try expect(tenderRatio < 1.0 && tenderRatio > 0.6,
                       "tender ratio \(tenderRatio)")
            try expect(coachRatio > 0.9 && coachRatio < 1.2,
                       "coach ratio \(coachRatio)")
            try expect(coachRatio > tenderRatio,
                       "coach should ride taller than the tender")
        }
    },
    Check("when a bundled car would dwarf the loco its length is squashed to the cap") {
        try MainActor.assumeIsolated {
            let cars = ModelConsist.load(carCount: 2) ?? []
            try expectEqual(cars.count, 2)
            let loco = try ModelAsset.sourceSize(
                at: modelAssetURL(named: "loco.usdz")!.path)
            let coach = try ModelAsset.sourceSize(
                at: modelAssetURL(named: "coach.usdz")!.path)
            let locoH = ProceduralLocomotive.size.height
            let locoDesignW = locoH * loco.width / loco.height
            let maxLen = locoDesignW * ModelConsist.maxCarLengthFactor
            // Uncapped the express coach is ~2 loco lengths — the cap
            // must bite, and only along x so height stays real.
            let uncappedCoachW = locoH * coach.width / loco.height
            try expect(uncappedCoachW > maxLen,
                       "premise: coach should exceed the cap")
            try expect(abs(cars[1].size.width - maxLen) < 1,
                       "coach width \(cars[1].size.width) vs cap \(maxLen)")
            try expect(cars[1].size.width < uncappedCoachW,
                       "coach was not length-capped")
            try expect(cars[1].node.scale.x < cars[1].node.scale.y,
                       "cap should squash x only")
            // The tender fits under the cap untouched.
            try expect(cars[0].size.width < maxLen,
                       "tender should keep its real length")
        }
    },
    Check("when model cars couple each pitch is half-widths plus the coupling gap") {
        try MainActor.assumeIsolated {
            let cars = ModelConsist.load(carCount: 3) ?? []
            let chain = ModelConsist.chain(cars: cars)
            try expectEqual(chain.childNodes.count, 3)
            // car-1 nearest the loco (smallest x), coupling order.
            let xs = chain.childNodes.map { CGFloat($0.position.x) }
            try expect(xs.count == 3 && xs[0] < xs[1] && xs[1] < xs[2],
                       "cars not ordered rearward: \(xs)")
            // First car's center sits half a width plus one
            // couplingGap past the chain origin (the loco's rear).
            if cars.count == 3 {
                try expect(abs(xs[0] - (Car.couplingGap
                                       + cars[0].size.width / 2)) < 0.5,
                           "first car pitch off: x=\(xs[0])")
                // Consecutive pitch = rear half + gap + front half.
                let pitch = xs[1] - xs[0]
                let want = (cars[0].size.width + cars[1].size.width) / 2
                    + Car.couplingGap
                try expect(abs(pitch - want) < 0.5,
                           "pitch \(pitch) vs expected \(want)")
            }
        }
    },
    Check("when model cars ride the consist their bottoms share the rail line") {
        try MainActor.assumeIsolated {
            let cars = ModelConsist.load(carCount: 3) ?? []
            let chain = ModelConsist.chain(cars: cars)
            for (i, car) in chain.childNodes.enumerated() {
                // Centered pivot: bottom = position.y - height/2 = 0.
                let wantY = i < cars.count ? cars[i].size.height / 2 : -1
                try expect(abs(CGFloat(car.position.y) - wantY) < 0.5,
                           "car \(car.name ?? "?") off the rail line")
            }
        }
    },
    Check("when model cars couple the chain length sums widths plus gaps") {
        try MainActor.assumeIsolated {
            let cars = ModelConsist.load(carCount: 3) ?? []
            let widthSum = cars.reduce(0) { $0 + $1.size.width }
            try expect(ModelConsist.chainLength(cars: cars)
                       == widthSum + 3 * Car.couplingGap)
            try expect(ModelConsist.chainLength(cars: []).isZero)
            try expect(ModelConsist.chain(cars: []).childNodes.isEmpty)
        }
    },
    Check("when the consist assets cannot be resolved load returns nil for a procedural fallback") {
        try MainActor.assumeIsolated {
            let cars = ModelConsist.load(carCount: 3,
                                         resolve: { _ in nil })
            try expect(cars == nil)
        }
    },
    Check("when one consist asset is missing load returns nil rather than a partial consist") {
        try MainActor.assumeIsolated {
            let dir = try writeSCNFixture()
            defer { try? FileManager.default.removeItem(at: dir) }
            let path = dir.appendingPathComponent("car.scn").path
            // The loco reference resolves but the tender does not.
            let cars = ModelConsist.load(carCount: 2) { name in
                name == "loco.usdz" ? path : nil
            }
            try expect(cars == nil)
        }
    },
    Check("when a consist asset is unreadable load returns nil") {
        try MainActor.assumeIsolated {
            let dir = try writeSCNFixture("car.txt")
            defer { try? FileManager.default.removeItem(at: dir) }
            let path = dir.appendingPathComponent("car.txt").path
            // Unsupported extension (.txt) fails sourceHeight.
            let cars = ModelConsist.load(carCount: 1) { _ in path }
            try expect(cars == nil)
        }
    },
    Check("when fixture scenes stand in for the bundled cars load names them tender then coaches") {
        try MainActor.assumeIsolated {
            let dir = try writeSCNFixture()
            defer { try? FileManager.default.removeItem(at: dir) }
            let path = dir.appendingPathComponent("car.scn").path
            let cars = ModelConsist.load(
                carCount: 3, resolve: { _ in path }) ?? []
            try expectEqual(cars.map { $0.node.name ?? "" },
                            ["model-tender", "model-coach-1",
                             "model-coach-2"])
        }
    },
    Check("when sourceHeight is asked for a missing file it throws file not found") {
        try MainActor.assumeIsolated {
            do {
                _ = try ModelAsset.sourceHeight(
                    at: "/nonexistent/sl-definitely-missing.usdz")
                try expect(false, "sourceHeight should throw")
            } catch let error as ModelAsset.LoadError {
                try expectEqual(error, .missingFile)
            }
        }
    },
    Check("when sourceHeight is asked for an unsupported extension it rejects it") {
        try MainActor.assumeIsolated {
            let dir = try writeSCNFixture("train.glb")
            defer { try? FileManager.default.removeItem(at: dir) }
            do {
                _ = try ModelAsset.sourceHeight(
                    at: dir.appendingPathComponent("train.glb").path)
                try expect(false, "sourceHeight should throw")
            } catch let error as ModelAsset.LoadError {
                try expectEqual(error, .unsupportedFormat("glb"))
            }
        }
    },
    Check("when sourceHeight is asked for an unparseable scene it throws unreadable") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sl-consist-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "not a scene".write(
            to: dir.appendingPathComponent("broken.usdz"),
            atomically: true, encoding: .utf8)
        try MainActor.assumeIsolated {
            do {
                _ = try ModelAsset.sourceHeight(
                    at: dir.appendingPathComponent("broken.usdz").path)
                try expect(false, "sourceHeight should throw")
            } catch let error as ModelAsset.LoadError {
                try expectEqual(error, .unreadable)
            }
        }
    },
    Check("when --model loco pulls three cars the scene chains a tender and two coaches behind the loco") {
        try MainActor.assumeIsolated {
            let chain = chain(in: renderedScene(
                for: ["sl", "--model", "loco", "-3"]))
            try expectEqual(chain?.childNodes.count, 3)
            let names = chain?.childNodes.map { $0.name ?? "" } ?? []
            try expect(names.contains("model-tender"),
                       "missing model-tender in \(names)")
            try expect(names.contains("model-coach-1")
                       && names.contains("model-coach-2"),
                       "missing coaches in \(names)")
            // Tender couples closest to the loco (smallest x).
            let xs = chain?.childNodes.map { CGFloat($0.position.x) } ?? []
            try expect(xs.count == 3 && xs[0] < xs[1] && xs[1] < xs[2],
                       "cars not ordered rearward: \(xs)")
            let tenderX = chain?.childNode(withName: "model-tender",
                                           recursively: false)?
                .position.x
            try expect(tenderX != nil && xs.first != nil
                       && abs(CGFloat(tenderX!) - xs[0]) < 0.5,
                       "tender is not nearest the loco")
        }
    },
    Check("when --model is absent the cars stay procedural") {
        try MainActor.assumeIsolated {
            let names = chain(in: renderedScene(for: ["sl", "-3"]))?
                .childNodes.map { $0.name ?? "" } ?? []
            try expect(names == ["car-1", "car-2", "car-3"],
                       "expected procedural cars, got \(names)")
        }
    },
    Check("when --model pulls more cars the rear of the consist reaches further right") {
        try MainActor.assumeIsolated {
            // The consist stays centered on its pose, so the loco's
            // own x never moves — the observable is the rear car's
            // world position, which the real car lengths push out.
            @MainActor func rearX(at args: [String]) -> CGFloat? {
                chain(in: renderedScene(for: args))?.childNodes
                    .map { CGFloat($0.worldPosition.x) }.max()
            }
            let few = rearX(at: ["sl", "--model", "loco", "-1"])
            let many = rearX(at: ["sl", "--model", "loco", "-5"])
            try expect(few != nil && many != nil
                       && many! > few!,
                       "-5 rear (\(many ?? -1)) did not pass "
                       + "-1 rear (\(few ?? -1))")
        }
    },
    Check("when a --model consist exits the ghost steam emitter still drops") {
        try MainActor.assumeIsolated {
            // A --model loco has no "smoke" child node, so the emitter
            // falls back to the train's world position.
            let runSpec = spec(["sl", "--model", "loco", "-1"])
            let renderer = SceneKitRenderer(spec: runSpec, stripWidth: 1000)
            let scene = (renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: runSpec) as? SCNView)?.scene
            let running = renderer.step(to: 9)
            let ghost = scene?.rootNode.childNode(
                withName: "ghost-steam", recursively: true)
            try expect(ghost != nil,
                       "no ghost-steam after exit (running=\(running))")
            try expect(!running, "consist never reported finished")
        }
    },
]
