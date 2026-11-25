# Spike A — ghost window (overlay existence + capture visibility)

**Question:** can a non-interactive CLI-spawned process show a
transparent click-through overlay at `.screenSaver` level, and does
`screencapture` capture it (the whole verification lane depends on it)?

**Tried:** skeleton `OverlayWindow` (borderless, non-opaque, clear
background, `.screenSaver` level, `.canJoinAllSpaces`, `.accessory`
activation policy) + `PlaceholderRenderer` red rect + `sl --freeze 2`
held by `scripts/shot /tmp/….png`.

**Result:** WORKS — verified on this machine, 2026-11-25: the frozen
frame showed the placeholder rect composited over third-party windows in
the bottom lane, and the `screencapture -x` PNG contained the
level-1000 window content. (The evidence PNG was later purged in #68 —
it was a full-desktop capture.)

**Decisions confirmed:**

- Overlay recipe in `Sources/OverlayKit/OverlayWindow.swift` is the
  final shape (not throwaway).
- `.accessory` activation policy from a bare SPM binary shows the window
  — no `.app` bundle needed.
- `screencapture -x` sees the overlay → `scripts/shot` is the
  verification lane for all UI work.
- `--freeze <t>` + SIGTERM kill works as the shot mechanism.

**Open follow-ups (moved to tasks):**

- SCNView transparent compositing → spike B.
- Fullscreen-Space behavior, click-through feel, multi-display → field
  checks in the overlay-hardening epic.
