import AppKit
import SLCore

/// Screen-lane geometry for the train's path. Pure geometry decisions
/// live here; the window recipe lives in `OverlayWindow`.
public enum OverlayGeometry {
    /// The lane a train crosses: a strip along the bottom of `screen`,
    /// spanning the frame's full width.
    public static func bottomStrip(on screen: NSScreen, height: CGFloat) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.minY,
               width: screen.frame.width, height: height)
    }

    /// Default target: the screen holding the frontmost window, else the
    /// main screen. `--all` traversal is feature work on top of this.
    public static func frontmostScreen() -> NSScreen? {
        NSScreen.main
    }
}
