import AppKit
import SLCore

/// Screen-lane geometry for the train's path. Pure geometry decisions
/// live here; the window recipe lives in `OverlayWindow`.
public enum OverlayGeometry {
    /// The lane strip's height as a fraction of screen height — the
    /// train is meant to fill a large share of the display, so the
    /// strip (and its click-through window) covers the bottom ~60%.
    public static let laneFraction: CGFloat = 0.6

    /// The design-lane height the scale-1 scene geometry was drawn
    /// against; `laneHeight(onScreenHeight:)` grows the strip beyond
    /// it and the renderer scales the train by the same ratio.
    public static let referenceLaneHeight: CGFloat = 180

    /// Lane strip height for a display `height` points tall.
    public static func laneHeight(onScreenHeight height: CGFloat) -> CGFloat {
        height * laneFraction
    }

    /// The angled camera elevation's sine (350/1059 in
    /// `SceneKitRenderer.addCamera`) — the `--angle` diagonal drifts
    /// vertically across the strip by `width × slope × tan(azimuth)`.
    public static let cameraTiltSlope: CGFloat = 0.33

    /// How far the `--angle` diagonal drifts vertically across a strip
    /// `stripWidth` points wide, in world units (== screen points at
    /// the renderer's 1:1 ortho scale).
    public static func diagonalRise(stripWidth: CGFloat,
                                    viewAngle: Double) -> CGFloat {
        stripWidth * cameraTiltSlope * tan(viewAngle * .pi / 180)
    }

    /// The lane window's height: the strip grown upward so the
    /// `--angle` diagonal path fits, capped at the screen's own
    /// height. `viewAngle` 0 returns the plain strip height.
    public static func viewHeight(laneHeight: CGFloat,
                                  stripWidth: CGFloat,
                                  viewAngle: Double,
                                  screenHeight: CGFloat) -> CGFloat {
        min(laneHeight + diagonalRise(
                stripWidth: stripWidth, viewAngle: viewAngle),
            screenHeight)
    }

    /// The lane a train crosses: a strip along the bottom of `screen`,
    /// spanning the frame's full width.
    public static func bottomStrip(on screen: NSScreen, height: CGFloat) -> NSRect {
        laneStrip(onScreenFrame: screen.frame, height: height)
    }

    /// The bottom strip of one screen, in global AppKit coordinates.
    public static func laneStrip(onScreenFrame frame: NSRect, height: CGFloat) -> NSRect {
        NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
    }

    /// The displays a run covers: every screen for `--all`, else only
    /// the frontmost one. Empty when no display is attached.
    public static func runScreens(all: Bool) -> [NSScreen] {
        all ? NSScreen.screens : frontmostScreen().map { [$0] } ?? []
    }

    /// The lane the train crosses, in global coordinates, built from
    /// screen frames: one rect spanning the leftmost screen's left edge
    /// to the rightmost screen's right edge, anchored at the lowest
    /// bottom edge. For a single frame this is exactly that screen's
    /// bottom strip. `nil` when `frames` is empty.
    public static func globalLane(frames: [NSRect], height: CGFloat) -> NSRect? {
        guard let minX = frames.map(\.minX).min(),
              let maxX = frames.map(\.maxX).max(),
              let minY = frames.map(\.minY).min() else { return nil }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: height)
    }

    /// `globalLane` over live screens.
    public static func lane(on screens: [NSScreen], height: CGFloat) -> NSRect? {
        globalLane(frames: screens.map(\.frame), height: height)
    }

    /// Default target: the screen holding the frontmost window, else the
    /// main screen.
    public static func frontmostScreen() -> NSScreen? {
        NSScreen.main
    }

    /// Global→window-local mapping: a lane window's content origin sits
    /// at its screen frame's bottom-left, so local = global − origin.
    public static func localRect(_ r: NSRect, onScreenFrame frame: NSRect) -> NSRect {
        r.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    /// Whether a global-space train rect appears on a display: it must
    /// intersect that screen's lane strip.
    public static func showsTrain(_ train: NSRect, onScreenFrame frame: NSRect,
                                  laneHeight: CGFloat) -> Bool {
        train.intersects(laneStrip(onScreenFrame: frame, height: laneHeight))
    }

    /// The Dock zones a run hops over, in lane-local x coordinates —
    /// one per screen whose bottom edge carries a Dock. A bottom Dock
    /// lifts `visibleFrame.minY` above `frame.minY`; a side Dock insets
    /// `minX`/`maxX` instead, so it never qualifies (Dock-on-bottom
    /// only). The Dock's width isn't public API, so the zone
    /// approximates it as a centered strip capped at 600pt.
    public static func dockZones(on screens: [NSScreen],
                                 lane: NSRect) -> [DockZone] {
        dockZones(
            screenFrames: screens.map(\.frame),
            visibleFrames: screens.map(\.visibleFrame),
            lane: lane)
    }

    /// `dockZones(on:lane:)` over plain rects — the pure core slChecks
    /// exercises without a live `NSScreen`.
    public static func dockZones(screenFrames: [NSRect],
                                 visibleFrames: [NSRect],
                                 lane: NSRect) -> [DockZone] {
        zip(screenFrames, visibleFrames).compactMap { frame, visible in
            dockZone(screenFrame: frame, visibleFrame: visible, lane: lane)
        }
    }

    /// One screen's Dock zone in lane-local x, or nil when the screen
    /// has no bottom Dock (or the inset is too small to be one).
    public static func dockZone(screenFrame frame: NSRect,
                                visibleFrame visible: NSRect,
                                lane: NSRect) -> DockZone? {
        let inset = visible.minY - frame.minY
        guard inset > 8 else { return nil }
        let width = min(frame.width, 600)
        let minGX = frame.midX - width / 2
        // The hop apex was tuned at 40pt on the 180pt design lane;
        // keep the same lane fraction as the strip grows.
        let apex = 40 * lane.height / referenceLaneHeight
        return DockZone(
            minX: minGX - lane.minX,
            maxX: minGX + width - lane.minX,
            apex: apex)
    }
}
