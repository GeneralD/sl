import AppKit
import SceneKit
import SLCore
import SLTestKit
import TrainScene

/// `RunSpec.parse` returns Result; unwrap or die — a bad fixture is a
/// broken check, not a test failure.
private func spec(_ args: [String]) -> RunSpec {
    switch RunSpec.parse(args) {
    case .success(let spec): return spec
    case .failure(let error): fatalError("fixture must parse: \(error)")
    }
}

private func allNames(_ node: SCNNode) -> Set<String> {
    var names = Set<String>()
    if let name = node.name { names.insert(name) }
    for child in node.childNodes { names.formUnion(allNames(child)) }
    return names
}

private func find(_ name: String, in node: SCNNode) -> SCNNode? {
    node.childNode(withName: name, recursively: true)
}

private func diffuseRGB(_ node: SCNNode) -> (CGFloat, CGFloat, CGFloat)? {
    guard let color = node.geometry?.materials.first?.diffuse.contents
            as? NSColor else { return nil }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b)
}

/// Builds the SceneKit renderer's scene for `args`, passing the same
/// spec to `makeView` — the way `sl` wires it.
@MainActor
private func scene(for args: [String]) -> SCNScene? {
    let run = spec(args)
    let renderer = SceneKitRenderer(spec: run, stripWidth: 1000)
    guard let view = renderer.makeView(
        in: NSRect(x: 0, y: 0, width: 1000, height: 180),
        spec: run) as? SCNView else { return nil }
    return view.scene
}

public let liveryChecks: [Check] = [
    Check("when built the TGV variant contains a bullet nose cabin body window band stripe and bogies") {
        let names = allNames(ProceduralTGV().node)
        for part in ["tgv-nose", "tgv-cabin", "tgv-body",
                     "tgv-window-near", "tgv-window-far",
                     "tgv-stripe-near", "tgv-stripe-far",
                     "tgv-roof", "tgv-bogie-1", "tgv-bogie-2",
                     "tgv-headlight"] {
            try expect(names.contains(part), "missing \(part)")
        }
    },
    Check("when built the TGV variant carries four named bogie wheels with axle-height pivots") {
        let tgv = ProceduralTGV().node
        var wheels: [SCNNode] = []
        func walk(_ n: SCNNode) {
            if let name = n.name, name.hasPrefix("wheel-tgv-"),
               !name.hasSuffix("-mesh") {
                wheels.append(n)
            }
            n.childNodes.forEach(walk)
        }
        walk(tgv)
        try expect(wheels.count == 4, "found \(wheels.count) wheels")
        for wheel in wheels {
            try expect(wheel.position.y > 0 && wheel.position.y < 15,
                       "\(wheel.name ?? "?") not at axle height")
            try expect(wheel.childNodes.contains { $0.geometry != nil },
                       "\(wheel.name ?? "?") has no mesh child")
        }
    },
    Check("when built the TGV variant pivot sits at track contact wider and lower than the D51") {
        let tgv = bounds(ProceduralTGV().node)
        let d51 = bounds(ProceduralLocomotive().node)
        try expect(abs(tgv.min.y) < 0.5, "min.y = \(tgv.min.y)")
        try expect(abs(tgv.min.x + tgv.max.x) < 1,
                   "not centered: \(tgv.min.x)…\(tgv.max.x)")
        let tgvH = tgv.max.y - tgv.min.y
        let d51H = d51.max.y - d51.min.y
        try expect(tgvH < d51H, "TGV height \(tgvH) not below D51 \(d51H)")
        let tgvW = tgv.max.x - tgv.min.x
        let d51W = d51.max.x - d51.min.x
        try expect(tgvW > d51W, "TGV width \(tgvW) not above D51 \(d51W)")
    },
    Check("when built at half scale the TGV bounding box halves") {
        let full = ProceduralTGV().node.boundingBox
        let half = ProceduralTGV(scale: 0.5).node.boundingBox
        let fullH = full.max.y - full.min.y
        let halfH = half.max.y - half.min.y
        try expect(abs(halfH - fullH / 2) < 1,
                   "half height \(halfH) vs \(fullH / 2)")
    },
    Check("when the spec carries -c the c51 livery paints the boiler vermilion edged in charcoal") {
        let d51 = diffuseRGB(find("boiler",
            in: ProceduralLocomotive(livery: .d51).node)!)
        let c51 = diffuseRGB(find("boiler",
            in: ProceduralLocomotive(livery: .c51).node)!)
        let d51Trim = diffuseRGB(find("chimney",
            in: ProceduralLocomotive(livery: .d51).node)!)
        let c51Trim = diffuseRGB(find("chimney",
            in: ProceduralLocomotive(livery: .c51).node)!)
        guard let d51, let c51, let d51Trim, let c51Trim else {
            try expect(false, "loco parts have no diffuse material")
            return
        }
        // Vermilion body: red dominant, clearly not the D51 black.
        try expect(c51.0 > 0.4 && c51.0 > c51.1 * 3,
                   "c51 boiler not vermilion: \(c51)")
        try expect(d51.0 < 0.2, "d51 boiler not black: \(d51)")
        // Red-edged: the trim goes charcoal, away from D51 brass.
        try expect(c51Trim.0 < 0.2 && c51Trim.1 < 0.2,
                   "c51 trim not charcoal: \(c51Trim)")
        try expect(d51Trim.1 > 0.3,
                   "d51 trim not brass: \(d51Trim)")
    },
    Check("when the spec carries -G the SceneKit renderer builds the TGV node instead of the D51") {
        try MainActor.assumeIsolated {
            guard let scene = scene(for: ["sl", "-G"]) else {
                try expect(false, "renderer produced no scene")
                return
            }
            try expect(scene.rootNode.childNode(
                withName: "procedural-tgv", recursively: true) != nil,
                "no procedural-tgv node in scene")
            try expect(scene.rootNode.childNode(
                withName: "procedural-locomotive", recursively: true) == nil,
                "D51 still present under -G")
        }
    },
    Check("when the spec is bare the SceneKit renderer still builds the D51 locomotive") {
        try MainActor.assumeIsolated {
            guard let scene = scene(for: ["sl"]) else {
                try expect(false, "renderer produced no scene")
                return
            }
            try expect(scene.rootNode.childNode(
                withName: "procedural-locomotive", recursively: true) != nil,
                "no procedural-locomotive node in scene")
            try expect(scene.rootNode.childNode(
                withName: "procedural-tgv", recursively: true) == nil,
                "TGV present without -G")
        }
    },
    Check("when the spec carries -c the SceneKit renderer paints the rendered boiler vermilion") {
        try MainActor.assumeIsolated {
            guard let scene = scene(for: ["sl", "-c"]),
                  let loco = scene.rootNode.childNode(
                    withName: "procedural-locomotive", recursively: true),
                  let boiler = find("boiler", in: loco),
                  let rgb = diffuseRGB(boiler) else {
                try expect(false, "renderer produced no c51 boiler")
                return
            }
            try expect(rgb.0 > 0.4 && rgb.0 > rgb.1 * 3,
                       "rendered boiler not vermilion: \(rgb)")
        }
    },
    Check("when the spec carries -G -l the TGV variant respects the little scale") {
        try MainActor.assumeIsolated {
            guard let scene = scene(for: ["sl", "-G", "-l"]),
                  let tgv = scene.rootNode.childNode(
                    withName: "procedural-tgv", recursively: true) else {
                try expect(false, "renderer produced no TGV node")
                return
            }
            let b = tgv.boundingBox
            try expect(b.max.y - b.min.y < 80,
                       "little TGV height \(b.max.y - b.min.y) not scaled")
        }
    },
]

private func bounds(_ node: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
    node.boundingBox
}
