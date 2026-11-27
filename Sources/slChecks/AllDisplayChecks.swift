import AppKit
import OverlayKit
import SLCore
import SLTestKit
import TrainScene

private let leftScreen = NSRect(x: 0, y: 0, width: 1000, height: 800)
private let rightScreen = NSRect(x: 1000, y: 0, width: 1000, height: 800)

private func spec(_ args: [String]) throws -> RunSpec {
    switch RunSpec.parse(args) {
    case .success(let spec): return spec
    case .failure(let error):
        try expect(false, "parse failed: \(error.message)")
        fatalError("unreachable: expect(false) always throws")
    }
}

public let allDisplayChecks: [Check] = [
    Check("when invoked with --all it requests every display") {
        let parsed = try spec(["sl", "--all"])
        try expect(parsed.allDisplays)
    },
    Check("when invoked without --all it keeps the single-display fallback") {
        let parsed = try spec(["sl"])
        try expect(!parsed.allDisplays)
    },
    Check("when --all is combined with --freeze it keeps the freeze offset") {
        let spec = try spec(["sl", "--all", "--freeze", "2.5"])
        try expect(spec.allDisplays)
        try expectEqual(spec.freeze, 2.5)
    },
    Check("when building the lane from screen frames it spans every screen at the lowest bottom edge") {
        let lane = OverlayGeometry.globalLane(frames: [
            NSRect(x: 0, y: 0, width: 1920, height: 1080),
            NSRect(x: -1280, y: -200, width: 1280, height: 1024),
        ], height: 180)
        try expectEqual(lane, NSRect(x: -1280, y: -200, width: 3200, height: 180))
    },
    Check("when no screens are attached the lane is nil") {
        try expect(OverlayGeometry.globalLane(frames: [], height: 180) == nil)
    },
    Check("when the lane is angled it grows the view by the diagonal's drift") {
        try expectEqual(OverlayGeometry.viewHeight(
            laneHeight: 180, stripWidth: 1000, viewAngle: 0,
            screenHeight: 800), 180)
        let grown = OverlayGeometry.viewHeight(
            laneHeight: 180, stripWidth: 1000, viewAngle: 30,
            screenHeight: 800)
        let drift = 1000 * OverlayGeometry.cameraTiltSlope * tan(30 * .pi / 180)
        try expect(abs(grown - (180 + drift)) < 1,
                   "view did not grow by the drift: \(grown)")
    },
    Check("when the diagonal would exceed the screen it caps the view at the screen height") {
        try expectEqual(OverlayGeometry.viewHeight(
            laneHeight: 600, stripWidth: 2000, viewAngle: 45,
            screenHeight: 800), 800)
    },
    Check("when the run screens are requested it returns at least one display") {
        try expect(!OverlayGeometry.runScreens(all: false).isEmpty)
        try expect(!OverlayGeometry.runScreens(all: true).isEmpty)
    },
    Check("when the launch screen is resolved it is one of the attached screens") {
        guard let screen = OverlayGeometry.launchScreen() else {
            try expect(false, "no launch screen")
            return
        }
        try expect(NSScreen.screens.contains(screen))
    },
    Check("when the lane is built over a live screen it sits at that screen's bottom edge") {
        guard let screen = OverlayGeometry.frontmostScreen() else {
            try expect(false, "no screen attached")
            return
        }
        let want = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                          width: screen.frame.width, height: 180)
        try expectEqual(OverlayGeometry.lane(on: [screen], height: 180), want)
        try expectEqual(OverlayGeometry.bottomStrip(on: screen, height: 180), want)
    },
    Check("when dock zones are computed over live screens they match the pure core") {
        guard let screen = OverlayGeometry.frontmostScreen() else {
            try expect(false, "no screen attached")
            return
        }
        let lane = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                          width: screen.frame.width, height: 180)
        let live = OverlayGeometry.dockZones(on: [screen], lane: lane)
        let pure = OverlayGeometry.dockZones(
            screenFrames: [screen.frame],
            visibleFrames: [screen.visibleFrame], lane: lane)
        try expectEqual(live.count, pure.count)
    },
    Check("when mapping a global rect onto a screen it subtracts the screen origin") {
        let local = OverlayGeometry.localRect(
            NSRect(x: 1784, y: 8, width: 220, height: 90),
            onScreenFrame: rightScreen)
        try expectEqual(local, NSRect(x: 784, y: 8, width: 220, height: 90))
    },
    Check("when the train rect intersects a screen's lane strip it reports the train visible") {
        let train = NSRect(x: 1784, y: 8, width: 220, height: 90)
        try expect(OverlayGeometry.showsTrain(
            train, onScreenFrame: rightScreen, laneHeight: 180))
        try expect(!OverlayGeometry.showsTrain(
            train, onScreenFrame: leftScreen, laneHeight: 180))
    },
    Check("when the stage updates it shows the train only on the screen it crosses") {
        try MainActor.assumeIsolated {
            let stage = MultiScreenTrain(
                lane: NSRect(x: 0, y: 0, width: 2000, height: 180), duration: 8)
            let left = NSView()
            let right = NSView()
            stage.attach(screenFrame: leftScreen, node: left)
            stage.attach(screenFrame: rightScreen, node: right)
            // t = 0.8s: global train center ≈ 1894 — over the right screen.
            stage.update(t: 0.8)
            try expect(right.isHidden == false, "right node hidden while crossed")
            try expect(left.isHidden, "left node visible while not crossed")
            try expect(abs(right.frame.minX - 784.4) < 1,
                       "right node not in screen-local coords: \(right.frame)")
            // t ≈ 6.15s: global train center ≈ 400 — over the left screen.
            stage.update(t: 6.15)
            try expect(!left.isHidden, "left node hidden while crossed")
            try expect(right.isHidden, "right node visible while not crossed")
        }
    },
    Check("when the stage updates past the duration it reports finished") {
        try MainActor.assumeIsolated {
            let stage = MultiScreenTrain(
                lane: NSRect(x: 0, y: 0, width: 2000, height: 180), duration: 8)
            try expect(stage.duration == 8)
            stage.update(t: 9)
            try expect(stage.finished)
        }
    },
]
