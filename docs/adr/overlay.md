# ADR: overlay window — how `sl` draws over everything

## Status

Accepted (Phase 0, golden scout + risk scout converged).

## Decision

A single borderless `NSWindow` per lane:

- `styleMask: .borderless`, `isOpaque = false`,
  `backgroundColor = .clear`, `hasShadow = false`
- `ignoresMouseEvents = true` — fully click-through
- `level = .screenSaver` (raw 1000) — above Dock, menu bar, normal and
  floating windows, and fullscreen-app Spaces
- `collectionBehavior`: `.canJoinAllSpaces`, `.stationary`,
  `.fullScreenAuxiliary`, `.ignoresCycle`
- `canBecomeKey` / `canBecomeMain` = false,
  `hidesOnDeactivate = false`
- App side: `NSApplication.shared.setActivationPolicy(.accessory)` —
  no Dock icon, no ⌘Tab entry, no focus steal. A bare SPM executable
  defaults to `.prohibited` (silently shows nothing) unless this is set
  before ordering windows front.
- No `.app` bundle, no Info.plist, no Accessibility/Screen-Recording
  permission — we paint over the screen, we never read it.

## Consequences

- Visible in screenshots and screen shares (that's the gag;
  `sharingType = .none` exists if a stealth flag is ever wanted).
- Lock screen and the actual screen saver still outrank level 1000 —
  accepted; `sl` is not meant to run over them.
- Recipe donor: `MrKai77/Loop` (GPL-3.0 — pattern reference only, no
  code copied), `farzaa/clicky` (MIT overlay repo), the
  `hamidzr` gist proving a bare `swiftc` binary can do it.

## Rejected

- `.statusBar` level (sits under menu-bar extras), per-screen windows
  (union-frame strip is simpler for the crossing), CGS private APIs
  (fragile, unneeded).
