import AppKit
import OverlayKit
import SLCore
import SLTestKit

private typealias RGBA = (UInt8, UInt8, UInt8, UInt8)

private let gray: RGBA = (90, 90, 90, 255)
private let red: RGBA = (220, 40, 40, 255)
private let blue: RGBA = (40, 40, 220, 255)

private func solidRep(_ w: Int, _ h: Int, color: RGBA) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: w * 4, bitsPerPixel: 32)!
    fill(rep, rect: (0, 0, w, h), color: color)
    return rep
}

/// Writes `rep` as a PNG at `path`; a failure leaves no file, which the
/// caller's existence/exit-code expects then catch.
private func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:])
    else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

/// Writes `color` into `rect` (x,y,w,h in pixels) of `rep`'s bitmap.
private func fill(_ rep: NSBitmapImageRep, rect: (Int, Int, Int, Int),
                  color: RGBA) {
    guard let data = rep.bitmapData else { return }
    let bpr = rep.bytesPerRow
    for y in rect.1..<(rect.1 + rect.3) {
        for x in rect.0..<(rect.0 + rect.2) {
            let o = y * bpr + x * 4
            data[o] = color.0
            data[o + 1] = color.1
            data[o + 2] = color.2
            data[o + 3] = color.3
        }
    }
}

public let shotEvidenceChecks: [Check] = [
    Check("when the lane rect is computed it covers the bottom lane plus margin of the display") {
        // 1512x982pt display captured at 2x → 3024x1964 px image.
        let rect = ShotEvidence.lanePixelRect(
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            imageSize: NSSize(width: 3024, height: 1964),
            margin: 60)
        try expect(rect != nil, "lane rect refused a matching capture")
        let r = rect!
        let stripPx = (OverlayGeometry.laneHeight(onScreenHeight: 982) + 60) * 2
        try expect(abs(r.width - 3024) < 1)
        try expect(abs(r.height - stripPx) < 1)
        try expect(abs(r.minY - (1964 - stripPx)) < 1)
        try expect(abs(r.minX) < 1)
    },
    Check("when the capture aspect does not match the screen the lane rect is refused") {
        // A portrait-ish image cannot be the claimed landscape display —
        // cropping it would fabricate evidence.
        let rect = ShotEvidence.lanePixelRect(
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            imageSize: NSSize(width: 1000, height: 3000))
        try expect(rect == nil,
                   "mismatched capture produced \(String(describing: rect))")
    },
    Check("when asked to parse a rect override it returns pixel bounds") {
        let r = ShotEvidence.parseRect("10,20,300,240")
        try expect(r != nil)
        try expect(r!.minX == 10 && r!.minY == 20
                   && r!.width == 300 && r!.height == 240)
        try expect(ShotEvidence.parseRect("10,20,300") == nil)
        try expect(ShotEvidence.parseRect("a,b,c,d") == nil)
    },
    Check("when the frozen captures hold a train that is gone afterwards the evidence fraction is high") {
        // a and b identical (frozen train), c without it.
        let a = solidRep(60, 40, color: gray)
        fill(a, rect: (10, 10, 20, 10), color: red)
        let b = solidRep(60, 40, color: gray)
        fill(b, rect: (10, 10, 20, 10), color: red)
        let c = solidRep(60, 40, color: gray)
        let fraction = ShotEvidence.trainEvidence(a, b, c)
        try expect(fraction != nil)
        try expect(fraction! > ShotEvidence.trainEvidenceThreshold,
                   "train evidence \(fraction!) below threshold")
    },
    Check("when the desktop churns between frozen captures the churn is not counted as evidence") {
        // a and b share the frozen train but differ in scattered
        // background pixels; c has neither train nor that churn.
        let a = solidRep(60, 40, color: gray)
        fill(a, rect: (10, 10, 20, 10), color: red)
        let b = solidRep(60, 40, color: gray)
        fill(b, rect: (10, 10, 20, 10), color: red)
        // Churn: scattered single pixels painted differently.
        for y in stride(from: 0, to: 40, by: 7) {
            for x in stride(from: 0, to: 60, by: 9) {
                if (x + y) % 3 == 0 { fill(a, rect: (x, y, 1, 1), color: blue) }
                if (x + y) % 3 == 1 { fill(b, rect: (x, y, 1, 1), color: blue) }
            }
        }
        let c = solidRep(60, 40, color: gray)
        let fraction = ShotEvidence.trainEvidence(a, b, c)
        try expect(fraction != nil)
        // Only the frozen blob counts — churn pixels fail a == b.
        try expect(fraction! < 0.2,
                   "churn leaked into evidence: \(fraction!)")
        try expect(fraction! > ShotEvidence.trainEvidenceThreshold)
    },
    Check("when nothing differs between frozen and post captures the evidence is zero") {
        let a = solidRep(60, 40, color: gray)
        let b = solidRep(60, 40, color: gray)
        let c = solidRep(60, 40, color: gray)
        try expect(ShotEvidence.trainEvidence(a, b, c) == 0)
    },
    Check("when the captures differ in size the evidence is refused") {
        let a = solidRep(60, 40, color: gray)
        let b = solidRep(60, 40, color: gray)
        let c = solidRep(60, 41, color: gray)
        try expect(ShotEvidence.trainEvidence(a, b, c) == nil)
    },
    Check("when the lane is rendered offscreen at a frozen time the snapshot covers it with train pixels") {
        try MainActor.assumeIsolated {
            guard case .success(let spec) =
                    RunSpec.parse(["sl", "--freeze", "2"]),
                  let rep = ShotEvidence.renderLanePNG(
                    spec: spec, freezeAt: 2, stripWidth: 1000)
            else {
                try expect(false, "offscreen render produced no snapshot")
                return
            }
            try expect(rep.pixelsWide >= 1000,
                       "render width \(rep.pixelsWide)")
            try expect(rep.pixelsHigh >= 180,
                       "render height \(rep.pixelsHigh)")
            let covered = ShotEvidence.subjectFraction(rep)
            try expect(covered != nil
                       && covered! >= ShotEvidence.renderEvidenceThreshold,
                       "render lane coverage \(String(describing: covered))")
        }
    },
    Check("when a display index is asked for it resolves a screen") {
        // `screencapture -D n` is 1-based into NSScreen.screens;
        // out-of-range indices fall back to the main screen.
        try expect(ShotEvidence.screen(display: 1) != nil)
        try expect(ShotEvidence.screen(display: 99) != nil)
    },
    Check("when two captures differ the diff fraction counts the changed pixels") {
        let a = solidRep(40, 30, color: gray)
        fill(a, rect: (4, 4, 8, 6), color: red)
        let b = solidRep(40, 30, color: gray)
        let fraction = ShotEvidence.diffFraction(a, b)
        try expect(fraction != nil)
        // Blob is 48px of 1200 → ~4% of pixels, sampled every other px.
        try expect(fraction! > 0.01 && fraction! < 0.2,
                   "diff fraction \(fraction!) out of range")
        try expect(ShotEvidence.diffFraction(a, solidRep(40, 31, color: gray)) == nil)
    },
    Check("when the lane command crops a full capture it writes a strip png") {
        let dir = NSTemporaryDirectory() + "shot-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let full = dir + "/full.png"
        let strip = dir + "/strip.png"
        let rep = solidRep(80, 60, color: gray)
        fill(rep, rect: (10, 45, 20, 10), color: red)
        writePNG(rep, to: full)
        let code = ShotEvidence.laneCommand(
            [full, strip, "--rect", "0,40,80,20"])
        try expect(code == 0, "laneCommand exited \(code)")
        try expect(FileManager.default.fileExists(atPath: strip))
        // The strip is 80x20 px — the bottom band where the lane lives.
        if let cropped = ShotEvidence.bitmapRep(at: strip) {
            try expect(cropped.pixelsWide == 80
                       && cropped.pixelsHigh == 20,
                       "strip is \(cropped.pixelsWide)x\(cropped.pixelsHigh)")
        } else {
            try expect(false, "strip is not a readable png")
        }
    },
    Check("when the lane command gets a capture that matches no display it refuses") {
        let dir = NSTemporaryDirectory() + "shot-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let full = dir + "/full.png"
        writePNG(solidRep(80, 60, color: gray), to: full)
        // 80x60 cannot be any landscape display's capture aspect.
        let code = ShotEvidence.laneCommand([full, dir + "/out.png"])
        try expect(code == 1, "laneCommand exited \(code)")
        try expect(!FileManager.default.fileExists(atPath: dir + "/out.png"))
    },
    Check("when the verify command sees a train in the lane it exits zero") {
        let dir = NSTemporaryDirectory() + "shot-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let a = solidRep(60, 40, color: gray)
        fill(a, rect: (10, 10, 20, 10), color: red)
        let b = solidRep(60, 40, color: gray)
        fill(b, rect: (10, 10, 20, 10), color: red)
        let c = solidRep(60, 40, color: gray)
        writePNG(a, to: dir + "/a.png")
        writePNG(b, to: dir + "/b.png")
        writePNG(c, to: dir + "/c.png")
        let code = ShotEvidence.verifyCommand(
            [dir + "/a.png", dir + "/b.png", dir + "/c.png"])
        try expect(code == 0, "verifyCommand exited \(code)")
    },
    Check("when the verify command sees an empty lane it exits nonzero") {
        let dir = NSTemporaryDirectory() + "shot-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        writePNG(solidRep(60, 40, color: gray), to: dir + "/a.png")
        writePNG(solidRep(60, 40, color: gray), to: dir + "/b.png")
        writePNG(solidRep(60, 40, color: gray), to: dir + "/c.png")
        let code = ShotEvidence.verifyCommand(
            [dir + "/a.png", dir + "/b.png", dir + "/c.png"])
        try expect(code == 1, "verifyCommand exited \(code)")
        try expect(ShotEvidence.verifyCommand([dir + "/a.png"]) == 2)
    },
    Check("when the render command renders a frozen lane it writes a png") {
        let dir = NSTemporaryDirectory() + "shot-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let out = dir + "/lane.png"
        let code = ShotEvidence.renderCommand([out, "--freeze", "2"])
        try expect(code == 0, "renderCommand exited \(code)")
        try expect(FileManager.default.fileExists(atPath: out))
        try expect(ShotEvidence.renderCommand([]) == 2)
        try expect(ShotEvidence.renderCommand([out, "--bogus"]) == 2)
    },
    Check("when the lane command is asked for too little it exits with usage") {
        try expect(ShotEvidence.laneCommand([]) == 2)
        try expect(ShotEvidence.laneCommand(["only-one.png"]) == 2)
        let dir = NSTemporaryDirectory() + "shot-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let full = dir + "/full.png"
        writePNG(solidRep(80, 60, color: gray), to: full)
        // A missing input and a malformed --rect are both usage errors.
        try expect(ShotEvidence.laneCommand(
            [dir + "/nope.png", dir + "/o.png"]) == 1)
        try expect(ShotEvidence.laneCommand(
            [full, dir + "/o.png", "--rect", "bogus"]) == 2)
        try expect(!FileManager.default.fileExists(atPath: dir + "/o.png"))
    },
    Check("when the verify command is handed unreadable captures it exits with usage") {
        let dir = NSTemporaryDirectory() + "shot-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try expect(ShotEvidence.verifyCommand([]) == 2)
        try expect(ShotEvidence.verifyCommand(
            [dir + "/a.png", dir + "/b.png"]) == 2)
        try expect(ShotEvidence.verifyCommand(
            [dir + "/a.png", dir + "/b.png", dir + "/c.png"]) == 2)
        // Size-mismatched but readable captures are a lane error, not usage.
        writePNG(solidRep(60, 40, color: gray), to: dir + "/a.png")
        writePNG(solidRep(60, 40, color: gray), to: dir + "/b.png")
        writePNG(solidRep(60, 41, color: gray), to: dir + "/c.png")
        try expect(ShotEvidence.verifyCommand(
            [dir + "/a.png", dir + "/b.png", dir + "/c.png"]) == 1)
    },
    Check("when the subject fraction is asked of a tiny rep it is refused") {
        try expect(ShotEvidence.subjectFraction(solidRep(2, 2, color: gray)) == nil)
    },
]
