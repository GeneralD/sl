import AppKit
import SceneKit
import SLCore
import SLTestKit
import TrainScene

private func accidentSpec() -> RunSpec {
    switch RunSpec.parse(["sl", "-a"]) {
    case .success(let spec): return spec
    case .failure(let error): fatalError("-a spec must parse: \(error)")
    }
}

private func defaultSpec() -> RunSpec {
    switch RunSpec.parse(["sl"]) {
    case .success(let spec): return spec
    case .failure(let error): fatalError("default spec must parse: \(error)")
    }
}

/// Builds a SceneKit renderer for `spec` and returns it with the train
/// node; the caller drives frames via `renderer.render(at:)`.
@MainActor
private func sceneParts(
    spec: RunSpec, width: CGFloat = 1000, height: CGFloat = 180
) -> (renderer: SceneKitRenderer, train: SCNNode)? {
    let renderer = SceneKitRenderer(spec: spec, stripWidth: width)
    guard let view = renderer.makeView(
        in: NSRect(x: 0, y: 0, width: width, height: height),
        spec: spec) as? SCNView,
        let scene = view.scene,
        let train = scene.rootNode.childNode(
            withName: "procedural-locomotive", recursively: true) else { return nil }
    return (renderer, train)
}

/// Counts descendant nodes named `name` under `node`.
private func countNamed(_ name: String, under node: SCNNode) -> Int {
    var count = node.name == name ? 1 : 0
    for child in node.childNodes {
        count += countNamed(name, under: child)
    }
    return count
}

/// Figures currently popped up: scale above a visible epsilon.
private func visibleScreamers(under node: SCNNode) -> Int {
    var count = node.name == "screamer" && node.scale.x > 0.05 ? 1 : 0
    for child in node.childNodes {
        count += visibleScreamers(under: child)
    }
    return count
}

public let screamerChecks: [Check] = [
    Check("when -a is parsed the spec requests screams for the audio engine") {
        let spec = accidentSpec()
        try expect(spec.accident)
        try expect(spec.wantScreams)
        try expect(!defaultSpec().wantScreams)
    },
    Check("when -a is on the scene holds screamer sprites inside car windows") {
        try MainActor.assumeIsolated {
            guard let parts = sceneParts(spec: accidentSpec()) else {
                try expect(false, "-a renderer produced no train")
                return
            }
            parts.renderer.render(at: 1)
            let windows = countNamed("car-window", under: parts.train)
            try expect(windows >= 3,
                       "only \(windows) car windows carry screamers")
            let figures = countNamed("screamer", under: parts.train)
            try expect(figures >= 6,
                       "only \(figures) screamer sprites in the windows")
        }
    },
    Check("when -a is on the screamers pop in and out over time") {
        try MainActor.assumeIsolated {
            guard let parts = sceneParts(spec: accidentSpec()) else {
                try expect(false, "-a renderer produced no train")
                return
            }
            var counts: [Int] = []
            var t = 0.0
            while t <= 2.4 {
                parts.renderer.render(at: t)
                counts.append(visibleScreamers(under: parts.train))
                t += 0.1
            }
            guard let low = counts.min(), let high = counts.max() else {
                try expect(false, "no frames sampled")
                return
            }
            try expect(high >= 3, "screamers never visible: max \(high)")
            try expect(low < high,
                       "screamers never hide: counts \(counts)")
        }
    },
    Check("when -a is on the loco rocks slightly") {
        try MainActor.assumeIsolated {
            guard let parts = sceneParts(spec: accidentSpec()) else {
                try expect(false, "-a renderer produced no train")
                return
            }
            // sin(2.6t)*0.045 peaks near t = pi/(2*2.6) ≈ 0.6.
            parts.renderer.render(at: 0.6)
            let rock = parts.train.eulerAngles.x
            try expect(abs(rock) > 0.005,
                       "loco never rocked: x=\(rock)")
            try expect(abs(rock) <= 0.08,
                       "rock too large: \(rock) rad")
        }
    },
    Check("when -a is off the scene has no screamers and the loco stays level") {
        try MainActor.assumeIsolated {
            guard let parts = sceneParts(spec: defaultSpec()) else {
                try expect(false, "plain renderer produced no train")
                return
            }
            parts.renderer.render(at: 0.6)
            parts.renderer.render(at: 1.2)
            try expect(countNamed("screamer", under: parts.train) == 0)
            try expect(countNamed("car-window", under: parts.train) == 0)
            try expect(parts.train.eulerAngles.x == 0,
                       "loco rocked without -a: \(parts.train.eulerAngles.x)")
        }
    },
]
