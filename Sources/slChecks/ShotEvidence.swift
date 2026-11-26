import AppKit
import OverlayKit
import SceneKit
import SLCore
import TrainScene

/// Evidence helpers behind `scripts/shot`'s hidden `slChecks` modes:
/// crop a full-display capture to the train lane strip and prove the
/// lane actually changed while the overlay ran. Living in slChecks
/// keeps the pixel math unit-checkable and `scripts/shot` shell-thin.
public enum ShotEvidence {
    /// Headroom above the lane kept for smoke and steam, in points.
    public static let defaultMargin: CGFloat = 60

    /// Two captures count as showing the train when at least this
    /// fraction of sampled pixels are static across the frozen run yet
    /// differ after it — the signature of overlay content over a
    /// churning desktop.
    public static let trainEvidenceThreshold = 0.01

    /// A rendered lane strip counts as showing the train above this
    /// fraction of subject pixels (the D51 covers ~10% of the lane).
    public static let renderEvidenceThreshold = 0.005

    /// Per-channel delta (0...1) that marks a pixel as changed.
    static let pixelDelta: CGFloat = 0.2

    /// The display `screencapture -D n` photographs, 1-based into
    /// `NSScreen.screens`; out-of-range falls back to the main screen.
    public static func screen(display: Int) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        return screens.indices.contains(display - 1)
            ? screens[display - 1]
            : NSScreen.main
    }

    /// Pixel rect (top-left origin) of the lane strip plus `margin`
    /// inside a capture of `screen`. The strip is `laneFraction` of the
    /// screen's height — pass `laneHeight` only to override. Returns
    /// nil when the image cannot be that display — aspect mismatch
    /// means a composite or wrong `-D`, and cropping it would produce
    /// garbage evidence.
    public static func lanePixelRect(
        screenFrame: NSRect, imageSize: NSSize,
        margin: CGFloat = defaultMargin,
        laneHeight: CGFloat? = nil
    ) -> NSRect? {
        guard screenFrame.width > 0, screenFrame.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let scaleX = imageSize.width / screenFrame.width
        let scaleY = imageSize.height / screenFrame.height
        guard abs(scaleX - scaleY) / scaleY < 0.02 else { return nil }
        let laneH = laneHeight
            ?? OverlayGeometry.laneHeight(onScreenHeight: screenFrame.height)
        let stripPx = (laneH + margin) * scaleY
        guard stripPx <= imageSize.height else { return nil }
        return NSRect(x: 0, y: imageSize.height - stripPx,
                      width: imageSize.width, height: stripPx)
    }

    /// Parses a `--rect x,y,w,h` override in image pixels
    /// (top-left origin). Nil on any malformed component.
    public static func parseRect(_ text: String) -> NSRect? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let x = Double(parts[0]), let y = Double(parts[1]),
              let w = Double(parts[2]), let h = Double(parts[3]),
              w > 0, h > 0 else { return nil }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    /// Per-channel delta (0...1) between two colors.
    static func delta(_ ca: NSColor, _ cb: NSColor) -> CGFloat {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0
        ca.getRed(&r1, green: &g1, blue: &b1, alpha: nil)
        cb.getRed(&r2, green: &g2, blue: &b2, alpha: nil)
        return abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
    }

    /// Fraction of sampled pixels whose RGB delta exceeds
    /// `pixelDelta`. Nil when the reps differ in size or are empty.
    public static func diffFraction(
        _ a: NSBitmapImageRep, _ b: NSBitmapImageRep
    ) -> Double? {
        guard a.pixelsWide == b.pixelsWide,
              a.pixelsHigh == b.pixelsHigh,
              a.pixelsWide > 0, a.pixelsHigh > 0 else { return nil }
        var sampled = 0
        var changed = 0
        for y in stride(from: 0, to: a.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: a.pixelsWide, by: 2) {
                sampled += 1
                guard let ca = a.colorAt(x: x, y: y),
                      let cb = b.colorAt(x: x, y: y) else { continue }
                if delta(ca, cb) > pixelDelta { changed += 1 }
            }
        }
        guard sampled > 0 else { return nil }
        return Double(changed) / Double(sampled)
    }

    /// Fraction of sampled pixels that are identical between the two
    /// frozen-run captures `a`/`b` yet differ from the post-run
    /// capture `c` — static overlay content (the train) over whatever
    /// the desktop did in between. Churning background fails the
    /// `a == b` test; a missing train fails the `a != c` test.
    /// Nil when the reps differ in size or are empty.
    public static func trainEvidence(
        _ a: NSBitmapImageRep, _ b: NSBitmapImageRep,
        _ c: NSBitmapImageRep
    ) -> Double? {
        guard a.pixelsWide == b.pixelsWide,
              a.pixelsHigh == b.pixelsHigh,
              a.pixelsWide == c.pixelsWide,
              a.pixelsHigh == c.pixelsHigh,
              a.pixelsWide > 0, a.pixelsHigh > 0 else { return nil }
        var sampled = 0
        var evidence = 0
        for y in stride(from: 0, to: a.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: a.pixelsWide, by: 2) {
                sampled += 1
                guard let ca = a.colorAt(x: x, y: y),
                      let cb = b.colorAt(x: x, y: y),
                      let cc = c.colorAt(x: x, y: y) else { continue }
                if delta(ca, cb) <= pixelDelta,
                   delta(ca, cc) > pixelDelta { evidence += 1 }
            }
        }
        guard sampled > 0 else { return nil }
        return Double(evidence) / Double(sampled)
    }

    /// `slChecks shot-lane <full.png> <out.png> [--display N]
    /// [--margin PT] [--rect x,y,w,h]` — crop `full.png` to the lane
    /// strip and write `out.png`. Exit 0 on success.
    public static func laneCommand(_ arguments: [String]) -> Int32 {
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data((
                "usage: slChecks shot-lane <full.png> <out.png> " +
                "[--display N] [--margin PT] [--rect x,y,w,h]\n").utf8))
            return 2
        }
        let fullPath = arguments[0]
        let outPath = arguments[1]
        var display = 1
        var margin = defaultMargin
        var rectText: String?
        var i = 2
        while i < arguments.count {
            switch arguments[i] {
            case "--display" where i + 1 < arguments.count:
                display = Int(arguments[i + 1]) ?? display
                i += 2
            case "--margin" where i + 1 < arguments.count:
                if let v = Double(arguments[i + 1]) { margin = CGFloat(v) }
                i += 2
            case "--rect" where i + 1 < arguments.count:
                rectText = arguments[i + 1]
                i += 2
            default:
                i += 1
            }
        }
        guard let rep = bitmapRep(at: fullPath) else {
            FileHandle.standardError.write(Data(
                "shot-lane: cannot read \(fullPath)\n".utf8))
            return 1
        }
        let imageSize = NSSize(width: rep.pixelsWide,
                               height: rep.pixelsHigh)
        let rect: NSRect?
        if let rectText {
            rect = parseRect(rectText)
            guard rect != nil else {
                FileHandle.standardError.write(Data((
                    "shot-lane: bad --rect '\(rectText)' " +
                    "(want x,y,w,h)\n").utf8))
                return 2
            }
        } else {
            guard let screen = screen(display: display) else {
                FileHandle.standardError.write(Data(
                    "shot-lane: no display attached\n".utf8))
                return 1
            }
            rect = lanePixelRect(screenFrame: screen.frame,
                                 imageSize: imageSize, margin: margin)
            guard rect != nil else {
                let gotW = Int(imageSize.width)
                let gotH = Int(imageSize.height)
                let wantW = Int(screen.frame.width)
                let wantH = Int(screen.frame.height)
                FileHandle.standardError.write(Data((
                    "shot-lane: capture \(gotW)x\(gotH) does not match " +
                    "display \(display) (\(wantW)x\(wantH)) — " +
                    "refusing to crop\n").utf8))
                return 1
            }
        }
        guard let cropped = crop(rep, to: rect!),
              let png = cropped.representation(using: .png,
                                             properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: outPath)))
                != nil else {
            FileHandle.standardError.write(Data(
                "shot-lane: cannot write \(outPath)\n".utf8))
            return 1
        }
        print("shot-lane: \(outPath) " +
              "(\(Int(rect!.width))x\(Int(rect!.height)) " +
              "at \(Int(rect!.minX)),\(Int(rect!.minY)))")
        return 0
    }

    /// `slChecks shot-verify <a.png> <b.png> <c.png>` — `a`/`b` are two
    /// captures of the frozen run, `c` the same strip after the overlay
    /// is gone. Exit 0 when static-then-gone pixels prove a train was
    /// in the lane, 1 when the evidence is missing.
    public static func verifyCommand(_ arguments: [String]) -> Int32 {
        guard arguments.count >= 3,
              let a = bitmapRep(at: arguments[0]),
              let b = bitmapRep(at: arguments[1]),
              let c = bitmapRep(at: arguments[2]) else {
            FileHandle.standardError.write(Data(
                "usage: slChecks shot-verify <a.png> <b.png> <c.png>\n"
                    .utf8))
            return 2
        }
        guard let fraction = trainEvidence(a, b, c) else {
            FileHandle.standardError.write(Data(
                "shot-verify: images differ in size or are empty\n".utf8))
            return 1
        }
        let pct = fraction * 100
        print(String(format: "shot-verify: %.2f%% train evidence", pct))
        guard fraction >= trainEvidenceThreshold else {
            FileHandle.standardError.write(Data(
                "shot-verify: no static overlay content — lane empty\n"
                    .utf8))
            return 1
        }
        return 0
    }

    static func bitmapRep(at path: String) -> NSBitmapImageRep? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else { return nil }
        return NSBitmapImageRep(data: data)
    }

    /// Crop `rep` to `rect` (pixels, top-left origin — the same space
    /// `lanePixelRect` and `--rect` speak). `CGImage.cropping` measures
    /// from the bottom-left, so the rect is flipped here; getting this
    /// wrong crops the top of the screen instead of the lane.
    static func crop(_ rep: NSBitmapImageRep,
                     to rect: NSRect) -> NSBitmapImageRep? {
        let bounds = NSRect(x: 0, y: 0,
                            width: rep.pixelsWide, height: rep.pixelsHigh)
        let r = rect.integral.intersection(bounds)
        guard !r.isNull, r.width > 0, r.height > 0,
              let cg = rep.cgImage else { return nil }
        let flipped = NSRect(x: r.minX,
                             y: CGFloat(rep.pixelsHigh) - r.maxY,
                             width: r.width, height: r.height)
        return cg.cropping(to: flipped).map(NSBitmapImageRep.init(cgImage:))
    }

    /// Fraction of sampled pixels differing from the corner pixel —
    /// the render's background. The snapshot comes back opaque (clear
    /// scene → white), so alpha can't mark the train; deviation from
    /// the background color can. Nil on an empty rep.
    public static func subjectFraction(_ rep: NSBitmapImageRep) -> Double? {
        guard rep.pixelsWide > 2, rep.pixelsHigh > 2,
              let bg = rep.colorAt(x: 2, y: 2) else { return nil }
        var sampled = 0
        var subject = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                sampled += 1
                guard let c = rep.colorAt(x: x, y: y),
                      delta(c, bg) > pixelDelta else { continue }
                subject += 1
            }
        }
        guard sampled > 0 else { return nil }
        return Double(subject) / Double(sampled)
    }

    /// Renders the lane strip offscreen at `freezeAt` and returns the
    /// snapshot — deterministic evidence with no desktop content at
    /// all. `stripWidth` defaults to the main screen's width in points;
    /// the strip height is the main screen's lane fraction.
    @MainActor
    public static func renderLanePNG(spec: RunSpec,
                                     freezeAt: TimeInterval,
                                     stripWidth: CGFloat? = nil)
        -> NSBitmapImageRep? {
        let screen = NSScreen.main
        let width = stripWidth ?? screen?.frame.width ?? 1920
        let laneH = OverlayGeometry.laneHeight(
            onScreenHeight: screen?.frame.height ?? 1080)
        let frame = NSRect(x: 0, y: 0, width: width, height: laneH)
        let renderer = SceneKitRenderer(
            spec: spec, stripWidth: width, laneHeight: laneH)
        guard let view = renderer.makeView(in: frame, spec: spec)
                as? SCNView else { return nil }
        view.frame = frame
        view.wantsLayer = true
        view.layer?.contentsScale = 2
        // Two frames: the wheelwork rig rolls on pose deltas, so a
        // lone render would leave wheels/rods untouched.
        renderer.render(at: freezeAt - 0.1)
        renderer.render(at: freezeAt)
        guard let tiff = view.snapshot().tiffRepresentation else {
            return nil
        }
        return NSBitmapImageRep(data: tiff)
    }

    /// `slChecks shot-render <out.png> [sl-args...]` — offscreen lane
    /// render for evidence. The sl args go to `RunSpec.parse` verbatim
    /// (`--freeze` picks the pose; default mid-run). Fails loudly when
    /// the render comes back without a train.
    public static func renderCommand(_ arguments: [String]) -> Int32 {
        guard let outPath = arguments.first else {
            FileHandle.standardError.write(Data((
                "usage: slChecks shot-render <out.png> [sl-args...]\n"
            ).utf8))
            return 2
        }
        let slArgs = Array(arguments.dropFirst())
        guard case .success(let spec) = RunSpec.parse(["sl"] + slArgs)
        else {
            FileHandle.standardError.write(Data((
                "shot-render: bad sl args: \(slArgs.joined(separator: " "))\n"
            ).utf8))
            return 2
        }
        let freezeAt = spec.freeze ?? 4
        // Everything UI-bound stays inside the isolated closure;
        // only the verdict and a message cross back.
        let outcome = MainActor.assumeIsolated { () -> (Int32, String) in
            guard let rep = renderLanePNG(spec: spec, freezeAt: freezeAt)
            else { return (1, "scene produced no snapshot") }
            guard let fraction = subjectFraction(rep),
                  fraction >= renderEvidenceThreshold
            else { return (1, "render is empty — no train to evidence") }
            guard let png = rep.representation(using: .png,
                                               properties: [:]),
                  (try? png.write(to: URL(fileURLWithPath: outPath)))
                    != nil
            else { return (1, "cannot write \(outPath)") }
            return (0, String(format: "%.1f%% lane covered",
                              fraction * 100))
        }
        guard outcome.0 == 0 else {
            FileHandle.standardError.write(Data(
                "shot-render: \(outcome.1)\n".utf8))
            return outcome.0
        }
        print("shot-render: \(outPath) (\(outcome.1))")
        return 0
    }
}
