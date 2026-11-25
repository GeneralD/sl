import AppKit
import SceneKit
import SLCore
import SLTestKit
import TrainScene

/// Every descendant name in the tree, for shape assertions.
private func allNames(_ node: SCNNode) -> Set<String> {
    var names = Set<String>()
    if let name = node.name { names.insert(name) }
    for child in node.childNodes { names.formUnion(allNames(child)) }
    return names
}

private func find(_ name: String, in node: SCNNode) -> SCNNode? {
    node.childNode(withName: name, recursively: true)
}

private func bounds(_ node: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
    node.boundingBox
}

private func wheelNodes(_ node: SCNNode) -> [SCNNode] {
    var wheels: [SCNNode] = []
    func walk(_ n: SCNNode) {
        if let name = n.name, name.hasPrefix("wheel-"), !name.hasSuffix("-mesh") {
            wheels.append(n)
        }
        n.childNodes.forEach(walk)
    }
    walk(node)
    return wheels
}

private func diffuseRGB(_ node: SCNNode) -> (CGFloat, CGFloat, CGFloat)? {
    guard let color = node.geometry?.materials.first?.diffuse.contents
            as? NSColor else { return nil }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b)
}

public let locomotiveChecks: [Check] = [
    Check("when built the locomotive contains boiler cab chimney steam dome sand dome cowcatcher running board and tender") {
        let names = allNames(ProceduralLocomotive().node)
        for part in ["boiler", "cab", "chimney", "steam-dome", "sand-dome",
                     "cowcatcher", "running-board", "tender"] {
            try expect(names.contains(part), "missing \(part)")
        }
    },
    Check("when built the locomotive has four drivers plus leading and trailing wheels named for animation") {
        let names = allNames(ProceduralLocomotive().node)
        let wheels = wheelNodes(ProceduralLocomotive().node)
        try expect(wheels.count == 6, "found \(wheels.count) wheels")
        for i in 1...4 {
            try expect(names.contains("wheel-driver-\(i)"))
        }
        try expect(names.contains("wheel-leading"))
        try expect(names.contains("wheel-trailing"))
    },
    Check("when built each wheel pivot carries a pre-rotated mesh child at axle height") {
        for wheel in wheelNodes(ProceduralLocomotive().node) {
            try expect(wheel.position.y > 0, "\(wheel.name ?? "?") not at axle height")
            let mesh = wheel.childNodes.first { $0.geometry != nil }
            try expect(mesh != nil, "\(wheel.name ?? "?") has no mesh child")
            let x = mesh?.eulerAngles.x ?? 0
            try expect(abs(x - .pi / 2) < 0.001,
                       "\(wheel.name ?? "?") mesh axle not on z")
        }
    },
    Check("when built the locomotive has named drive and coupling rods") {
        let names = allNames(ProceduralLocomotive().node)
        try expect(names.contains("rod-drive"))
        try expect(names.contains("rod-coupling"))
    },
    Check("when built the locomotive pivot sits at track contact sized to the lane") {
        let b = bounds(ProceduralLocomotive().node)
        try expect(abs(b.min.y) < 0.5, "min.y = \(b.min.y)")
        try expect(b.max.y > 140 && b.max.y < 160,
                   "max.y = \(b.max.y), want ~150")
        try expect(b.max.x - b.min.x > 300,
                   "width = \(b.max.x - b.min.x)")
        try expect(abs(b.min.x + b.max.x) < 1,
                   "not centered: \(b.min.x)…\(b.max.x)")
    },
    Check("when built at half scale the locomotive bounding box halves") {
        let full = bounds(ProceduralLocomotive().node)
        let half = bounds(ProceduralLocomotive(scale: 0.5).node)
        let fullH = full.max.y - full.min.y
        let halfH = half.max.y - half.min.y
        try expect(abs(halfH - fullH / 2) < 1,
                   "half height \(halfH) vs \(fullH / 2)")
    },
    Check("when built with the c51 livery the boiler paint differs from d51") {
        let d51 = diffuseRGB(find("boiler", in: ProceduralLocomotive(livery: .d51).node)!)
        let c51 = diffuseRGB(find("boiler", in: ProceduralLocomotive(livery: .c51).node)!)
        guard let d51, let c51 else {
            try expect(false, "boiler has no diffuse material")
            return
        }
        let differs = d51.0 != c51.0 || d51.1 != c51.1 || d51.2 != c51.2
        try expect(differs, "c51 and d51 share boiler paint")
    },
    Check("when the SceneKit renderer is asked for its view the locomotive wheel tree rides along") {
        try MainActor.assumeIsolated {
            let renderer = SceneKitRenderer(
                spec: RunSpec.parse(["sl"]), stripWidth: 1000)
            guard let view = renderer.makeView(
                in: NSRect(x: 0, y: 0, width: 1000, height: 180),
                spec: RunSpec.parse(["sl"])) as? SCNView,
                  let scene = view.scene else {
                try expect(false, "renderer produced no scene")
                return
            }
            let loco = scene.rootNode.childNode(
                withName: "procedural-locomotive", recursively: true)
            try expect(loco != nil, "no locomotive node in scene")
            try expect(find("wheel-driver-1", in: loco!) != nil,
                       "wheel hooks missing from rendered loco")
            try expect(find("rod-drive", in: loco!) != nil,
                       "rod hooks missing from rendered loco")
        }
    },
]
