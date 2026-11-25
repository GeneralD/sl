import AppKit
import SLCore

/// Screen-lane geometry for the train's path. Pure geometry decisions
/// live here; the window recipe lives in `OverlayWindow`.
public enum OverlayGeometry {
    /// Height of the lane strip on every display.
    public static let laneHeight: CGFloat = 180

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
}
