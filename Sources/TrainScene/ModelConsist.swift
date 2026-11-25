import SceneKit

/// The bundled-car consist for `--model` runs (`-<n>`): the tevy.dev
/// USDZ tender and coaches under `share/sl/models/`, coupled behind
/// the locomotive in place of the procedural `Car.cars` chain.
///
/// Heights keep real-world proportion to the loco: each car is
/// normalized so `carHeight / locoHeight` matches the assets'
/// bounding boxes, with the bundled `loco.usdz` as the meter
/// reference — so the tender rides lower than the loco and the coach
/// keeps its real height. Length is capped at `maxCarLengthFactor`
/// loco lengths, squashed along x only: the 27 m express coach is
/// genuinely twice the locomotive long, which would swamp the lane.
public enum ModelConsist {
    /// One coupled car: the normalized model node plus its size in
    /// design units — the space `locoScale` then scales, same as
    /// `ModelAsset.Loaded.size`. `size.width` already reflects the
    /// length cap.
    public struct Car {
        public let node: SCNNode
        public let size: CGSize
    }

    /// No car runs longer than this many locomotive lengths — the
    /// express coach's real ~2:1 ratio is scaled down to stay sane
    /// on screen (issue #75).
    public static let maxCarLengthFactor: CGFloat = 1.5

    /// Bundled asset file names in coupling order for `n` requested
    /// cars: the tender always couples closest to the loco, coaches
    /// fill the rest. `--cars 0` yields an empty consist.
    public static func assetNames(carCount n: Int) -> [String] {
        guard n > 0 else { return [] }
        guard n > 1 else { return ["tender.usdz"] }
        return ["tender.usdz"]
            + Array(repeating: "coach.usdz", count: n - 1)
    }

    /// Loads the consist from the bundled `share/sl/models/`
    /// directory, or nil when the assets cannot be resolved or
    /// parsed — callers fall back to procedural cars rather than
    /// running a partial consist.
    @MainActor
    public static func load(carCount n: Int) -> [Car]? {
        load(carCount: n) { modelAssetURL(named: $0)?.path }
    }

    /// `resolve` maps an asset file name to a filesystem path — the
    /// seam checks use to point the consist at fixture scenes.
    @MainActor
    public static func load(carCount n: Int,
                            resolve: (String) -> String?) -> [Car]? {
        guard let reference = locoReferenceSize(resolve: resolve)
        else { return nil }
        let designLocoHeight = ProceduralLocomotive.size.height
        let locoDesignWidth = designLocoHeight
            * reference.width / reference.height
        let maxCarLength = locoDesignWidth * maxCarLengthFactor
        var cars: [Car] = []
        var coach = 0
        for name in assetNames(carCount: n) {
            guard let path = resolve(name),
                  let raw = try? ModelAsset.sourceSize(at: path),
                  raw.width > 0, raw.height > 0,
                  let loaded = try? ModelAsset.loadTrain(
                      at: path,
                      targetHeight: designLocoHeight
                          * raw.height / reference.height)
            else { return nil }
            if name == "tender.usdz" {
                loaded.node.name = "model-tender"
            } else {
                coach += 1
                loaded.node.name = "model-coach-\(coach)"
            }
            cars.append(lengthCapped(loaded, maxLength: maxCarLength))
        }
        return cars
    }

    /// Squashes a car's x axis when its design length exceeds
    /// `maxLength`, keeping height and proportions — the node pivot
    /// stays centered, so only `scale.x` and the reported width move.
    private static func lengthCapped(
        _ loaded: ModelAsset.Loaded, maxLength: CGFloat
    ) -> Car {
        let factor = min(1, maxLength / loaded.size.width)
        guard factor < 1 else {
            return Car(node: loaded.node, size: loaded.size)
        }
        var scale = loaded.node.scale
        scale.x *= factor
        loaded.node.scale = scale
        return Car(
            node: loaded.node,
            size: CGSize(width: loaded.size.width * factor,
                         height: loaded.size.height))
    }

    /// Design-space length the chain adds behind the loco's rear
    /// edge — every car's width plus one `couplingGap`, the same
    /// accounting `Car.chainLength` uses for procedural cars.
    public static func chainLength(cars: [Car]) -> CGFloat {
        cars.reduce(0) { $0 + $1.size.width }
            + CGFloat(cars.count) * TrainScene.Car.couplingGap
    }

    /// The `car-chain` node: cars trailing +x in coupling order, each
    /// bottom on the rail line (the chain origin sits at the loco's
    /// rear edge at track contact), spaced by `couplingGap` like
    /// `Car.cars`.
    public static func chain(cars: [Car]) -> SCNNode {
        let chain = SCNNode()
        chain.name = "car-chain"
        var x = TrainScene.Car.couplingGap
        for car in cars {
            car.node.position = SCNVector3(
                Float(x + car.size.width / 2),
                Float(car.size.height / 2), 0)
            chain.addChildNode(car.node)
            x += car.size.width + TrainScene.Car.couplingGap
        }
        return chain
    }

    /// Raw size of the `loco.usdz` asset — the fixed meter reference
    /// every car's proportion is measured against, whatever `--model`
    /// file the user actually supplied.
    @MainActor
    private static func locoReferenceSize(
        resolve: (String) -> String?
    ) -> CGSize? {
        guard let path = resolve("loco.usdz"),
              let size = try? ModelAsset.sourceSize(at: path),
              size.width > 0, size.height > 0
        else { return nil }
        return size
    }
}
