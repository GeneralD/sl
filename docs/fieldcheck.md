# Field check — `sl --all` multi-display traversal

`--all` puts one overlay window on every display and drives a single
train through global screen coordinates. This procedure needs a second
physical display; on a single-display machine `--all` degenerates to the
normal run and is covered by `slChecks` + `scripts/shot` instead.

## Setup

1. Connect a second display and arrange it side-by-side with the main
   display (System Settings → Displays → Arrangement). Note which side.
2. Build once: `scripts/run -- --version` (warms the shared scratch).

## Checks

1. `scripts/run -- --all` — the train enters at the right edge of the
   rightmost display, crosses the seam onto the left display, and exits
   off the left edge. It must never appear on a display it isn't
   crossing, nor in the dead space between non-contiguous displays.
2. Swap the displays' left/right positions in Arrangement and re-run —
   the lane follows the physical layout (global `NSScreen` frames), not
   `NSScreen.screens` ordering.
3. `scripts/run` (no `--all`) — unchanged: the train only crosses the
   display holding the frontmost window.
4. Frozen frame per display:
   `scripts/shot docs/shots/27-all.png -- --all`
   captures the main display; for the other display use
   `screencapture -D <display> -x out.png` while `sl --all --freeze 2`
   holds the train mid-crossing.

## Known limits

- Displays at different heights/vertical offsets share one global lane
  anchored at the lowest bottom edge; a display whose strip doesn't
  intersect the train's global rect simply doesn't show it.
- Mirrored/rotated arrangements are untested — the lane math assumes
  axis-aligned frames.
