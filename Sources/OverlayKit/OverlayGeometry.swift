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
    /// the one holding the terminal `sl` was typed into. Empty when no
    /// display is attached.
    public static func runScreens(all: Bool) -> [NSScreen] {
        all ? NSScreen.screens : launchScreen().map { [$0] } ?? []
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

    /// The screen holding the terminal window `sl` was typed into.
    /// `NSScreen.main` tracks keyboard focus, which misses the right
    /// display on multi-monitor setups, so the terminal is located
    /// directly: the ancestor PID chain is walked to the nearest GUI
    /// process (the terminal app) and its frontmost window's frame is
    /// read from CGWindowList. Inside tmux the chain dies at the
    /// server, so the client PID is used instead; `TERM_PROGRAM` and
    /// the frontmost app are shallower fallbacks. When no candidate
    /// yields a window — automation, remote shells — the keyboard-
    /// focus screen is the final answer.
    public static func launchScreen() -> NSScreen? {
        launchPids()
            .lazy
            .compactMap(frontmostWindowFrame(ofAppPid:))
            .compactMap(screen(holdingQuartzFrame:))
            .first ?? frontmostScreen()
    }

    /// App PIDs that should own the terminal window, best guess first:
    /// the nearest GUI-app ancestor of this process, the launch
    /// context's `__CFBundleIdentifier` (inherited through tmux/zellij
    /// servers), the tmux client's GUI ancestor, the TERM_PROGRAM-
    /// declared app, and the frontmost application. `environment`
    /// defaults to the process env — slChecks pins the candidate arms
    /// with synthetic envs (CI has no Ghostty/zellij to resolve
    /// organically).
    public static func launchPids(
        environment env: [String: String] = ProcessInfo.processInfo
            .environment) -> [pid_t]
    {
        launchPidCandidates(environment: env)
            .reduce(into: [pid_t]()) { pids, pid in
                if !pids.contains(pid) { pids.append(pid) }
            }
    }

    private static func launchPidCandidates(
        environment env: [String: String]) -> [pid_t]
    {
        [
            guiAncestor(of: getppid()),
            env["__CFBundleIdentifier"].flatMap(runningPid(ofBundleId:)),
            env["TMUX"] == nil ? nil : tmuxClientPid().flatMap(guiAncestor),
            env["TERM_PROGRAM"].flatMap { terminalBundleIds[$0] }
                .flatMap(runningPid(ofBundleId:)),
            NSWorkspace.shared.frontmostApplication?.processIdentifier,
        ].compactMap { $0 }
    }

    /// TERM_PROGRAM identifier → bundle ID, for launches whose
    /// ancestor chain can't be walked (detached shells, helpers).
    private static let terminalBundleIds: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "vscode": "com.microsoft.VSCode",
        "WezTerm": "com.github.wez.wezterm",
        "ghostty": "com.mitchellh.ghostty",
        "kitty": "net.kovidgoyal.kitty",
        "alacritty": "org.alacritty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "Hyper": "co.zeit.hyper",
        "zed": "dev.zed.Zed",
    ]

    /// The PID of a running app for `bundleId`, if one exists —
    /// exposed for slChecks like the other pure seams.
    public static func runningPid(ofBundleId bundleId: String) -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId)
            .first?.processIdentifier
    }

    /// The nearest GUI-app ancestor of `pid` — the terminal — or nil
    /// when the chain reaches launchd without one (remote or
    /// daemonized shells).
    public static func guiAncestor(of pid: pid_t) -> pid_t? {
        var pid = pid, seen: Set<pid_t> = []
        while pid > 1, seen.insert(pid).inserted {
            if let app = NSRunningApplication(processIdentifier: pid),
               app.activationPolicy != .prohibited { return pid }
            guard let ppid = parentPid(of: pid), ppid != pid else { break }
            pid = ppid
        }
        return nil
    }

    /// `pid`'s parent via libproc, or nil once the process is gone.
    public static func parentPid(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              let ppid = pid_t(exactly: info.pbi_ppid)
        else { return nil }
        return ppid
    }

    /// The foreground tmux client's PID. Panes hang off the *server*,
    /// so inside tmux the ancestor walk dies there; the client is the
    /// terminal app's child and keeps a walkable chain.
    private static func tmuxClientPid() -> pid_t? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["tmux", "display-message", "-p", "#{client_pid}"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard let _ = try? task.run() else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return Int32(String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The frontmost normal-ish window of `pid` in Quartz display
    /// coordinates (top-left origin). CGWindowList is front-to-back,
    /// so the first owned window is the one being typed into. Terminals
    /// don't all sit at layer 0 — Ghostty's main window reports layer
    /// 3 — so any non-negative layer counts; the 100pt size floor
    /// skips utility surfaces (menu extras, quick-look helpers).
    public static func frontmostWindowFrame(ofAppPid pid: pid_t)
        -> CGRect?
    {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] else { return nil }
        return list.lazy.compactMap { entry -> CGRect? in
            guard entry[kCGWindowOwnerPID as String] as? Int == Int(pid),
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer >= 0,
                  let bounds = entry[kCGWindowBounds as String]
                    as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width >= 100, frame.height >= 100
            else { return nil }
            return frame
        }.first
    }

    /// The screen holding most of `quartzFrame` — the pure core
    /// slChecks exercises. CGWindowList space is top-left-origin while
    /// `NSScreen.frame` is bottom-left-origin with the primary screen
    /// at (0,0); a window spanning displays counts toward the side it
    /// mostly occupies.
    public static func screen(holdingQuartzFrame quartzFrame: CGRect)
        -> NSScreen?
    {
        guard let primary = NSScreen.screens
            .first(where: { $0.frame.origin == .zero })
        else { return nil }
        let frame = CGRect(
            x: quartzFrame.minX,
            y: primary.frame.height - quartzFrame.maxY,
            width: quartzFrame.width, height: quartzFrame.height)
        return NSScreen.screens
            .max(by: { overlap($0, with: frame) < overlap($1, with: frame) })
            .flatMap { $0.frame.intersects(frame) ? $0 : nil }
    }

    /// Shared-area of `screen.frame` and `frame` — the tie-breaker for
    /// a window straddling displays.
    private static func overlap(_ screen: NSScreen, with frame: CGRect)
        -> CGFloat
    {
        let hit = screen.frame.intersection(frame)
        return hit.width * hit.height
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
