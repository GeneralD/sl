# Field-check procedures — overlay hardening

Repeatable manual + shot protocols for the experiential properties of the
ghost window (epic #10). Each check lists concrete commands, expected
behavior, and an evidence slot under `docs/shots/`. Run them on the host
with a real display — headless/SSH cannot exercise any of this.

## Conventions

- Build/run from the repo root; `scripts/run` builds the debug binary and
  execs it, `scripts/shot <png>` freezes a run mid-frame and captures the
  screen (one shot at a time — `shot.lock` serializes).
- A **live run** is `scripts/run` (the train crosses and `sl` exits on its
  own). A **held run** is `scripts/run --freeze 300` — the window stays up
  until `kill <pid>` or the freeze elapses; use it whenever you need time
  to click, switch Spaces, or start another app.
- Evidence files land in `docs/shots/`; name them `NN-<check>.png`.
- Record each run in the **Result** line: date, machine, pass/fail, and
  the evidence filename.

---

## 1. Click-through

Clicks must pass through the overlay to whatever window sits under the
lane — the train is decoration, never a hit target.

### Steps

1. Open a text window low on the screen so it intersects the lane
   (the bottom ~180 pt of the main display):

   ```sh
   osascript -e 'tell application "TextEdit" to activate' \
     -e 'tell application "TextEdit" to make new document' \
     -e 'tell application "TextEdit" to set bounds of window 1 to {200, 960, 1100, 1070}'
   ```

2. Start a held run: `scripts/run --freeze 300` (note the PID).
3. Click inside the TextEdit window at a point covered by the lane, then
   type. Via System Events:

   ```sh
   osascript -e 'tell application "System Events" to click at {550, 1015}' \
     -e 'tell application "System Events" to keystroke "sl-clickthrough-ok"'
   ```

   Or do it by hand: click the TextEdit window where the train is crossing,
   then type.
4. Read the document back:

   ```sh
   osascript -e 'tell application "TextEdit" to get text of document 1'
   ```

### Expected

- The click focuses TextEdit (it becomes the active app) and the typed
  text appears in the document — nothing is swallowed by the overlay.
- The train keeps animating during and after the click; `sl` never takes
  focus, never appears in ⌘Tab, and `canBecomeKey`/`canBecomeMain` stay
  false.

### Evidence

`docs/shots/18-clickthrough.png` — train lane composited over the
TextEdit window that received the click. (Purged in #68: it was a
full-desktop capture; future evidence is lane-cropped.)

### Result

- 2026-11-25, this machine (macOS 26, dual 1920×1080): **PASS** — click at
  `{550, 1015}` inside the lane focused TextEdit and `sl-clickthrough-ok`
  was typed into the document. Evidence: `docs/shots/18-clickthrough.png`.

---

## 2. Fullscreen-Space behavior

The overlay must stay visible when a fullscreen app owns the current
Space (`.fullScreenAuxiliary` + `.canJoinAllSpaces` +
`.ignoresCycle` in `OverlayWindow.collectionBehavior`).

### Steps

1. Open a fullscreen app — Safari is the cheapest:

   ```sh
   open -a Safari
   ```

   Then enter fullscreen (green traffic-light button, or ⌃⌘F).
2. With the fullscreen Space active, start a live run: `scripts/run`.
3. While it crosses, capture evidence mid-run. Either take the shot while
   a held run is up (`scripts/run --freeze 300` + `scripts/shot`), or use
   `scripts/shot docs/shots/NN-fullscreen-space.png` which freezes and
   captures in one step — but note `scripts/shot` captures whatever Space
   is visible, so enter the fullscreen Space first.
4. Switch Spaces (Ctrl+←/→ or swipe) while a held run is up and confirm
   the train is on every Space, not just the one where `sl` started.

### Expected

- The train renders **over** the fullscreen app's content on its own
  Space.
- The overlay follows across Spaces — it does not pin to the Space active
  at launch.
- The fullscreen app is unaffected: no focus steal, no menu-bar anomaly,
  exiting fullscreen works normally.

### Evidence

`docs/shots/NN-fullscreen-space.png` — lane visible over a fullscreen app.

### Result

- _pending — run on host._

---

## 3. Multi-display layout (`--all`)

With more than one display connected, `sl --all` must place a lane on
every screen, not just the main one.

### Steps

1. Connect a second display (or verify two are attached):

   ```sh
   system_profiler SPDisplaysDataType | grep -c "UI Looks like"
   ```

2. Start a held run on all displays: `scripts/run --all --freeze 300`.
   (Bare `scripts/run` targets only the main/frontmost screen — that
   single-display behavior is the baseline, check it separately.)
3. Watch the bottom edges while the train crosses: it enters at the
   right edge of the **rightmost** display, crosses the seam onto the
   left display, and exits off the left edge — one train, one global
   lane spanning every screen (`OverlayGeometry.globalLane`), not one
   independent train per display.
4. Swap the displays' left/right positions in Arrangement and re-run —
   the lane follows the physical layout (global `NSScreen` frames), not
   `NSScreen.screens` ordering.
5. Capture each display. `screencapture` can target one display:

   ```sh
   screencapture -x -D 1 docs/shots/NN-displays-main.png
   screencapture -x -D 2 docs/shots/NN-displays-secondary.png
   ```

   (`-D` numbering follows the display arrangement in
   System Settings → Displays.) Time the captures for `t ≈ 0.8` (train
   over the right screen) and `t ≈ 6.2` (over the left screen) of the
   8 s crossing — or just hold with `--freeze <t>`.

### Expected

- One lane window per connected display; the single train is visible on
  a display only while its global rect intersects that display's strip.
- No lane on a display that is asleep or disconnected mid-run (windows
  must follow display connect/disconnect without crashing).
- Without `--all`: exactly one lane, on the main display.

### Known limits

- Displays at different heights/vertical offsets share one global lane
  anchored at the lowest bottom edge; a display whose strip doesn't
  intersect the train's global rect simply doesn't show it.
- Mirrored/rotated arrangements are untested — the lane math assumes
  axis-aligned frames.

### Evidence

`docs/shots/NN-displays-main.png`, `docs/shots/NN-displays-secondary.png`.

### Result

- _pending — run on a host with two displays._

---

## 4. Screen-capture visibility + `--stealth`

By default the overlay **is** captured — screenshots and screen shares
show the train (that is the gag; see `docs/adr/overlay.md`). `sl
--stealth` opts out via `sharingType = .none` so the window is excluded
from capture while still visible on the physical display.

### Steps

1. Baseline capture — held run, then grab the screen:

   ```sh
   scripts/run --freeze 60 &
   sleep 3
   screencapture -x /tmp/sl-visible.png
   kill %1
   ```

   Open `/tmp/sl-visible.png` — the train must be in it.
   (`scripts/shot docs/shots/NN-capture-visible.png` does the same in one
   step and is the preferred evidence lane.)
2. Stealth run — same procedure with the flag:

   ```sh
   scripts/run --stealth --freeze 60 &
   sleep 3
   screencapture -x /tmp/sl-stealth.png
   kill %1
   ```

3. Look at the physical display during step 2 (or record it): the train
   must still be visibly crossing even though the PNG lacks it.

### Expected

- Default run: train present in `screencapture` output **and** in any
  screen share / recording.
- `--stealth` run: train absent from `screencapture` output and screen
  shares, still present on the physical screen.
- Stealth must not change click-through, window level, or run duration.

### Evidence

`docs/shots/NN-capture-visible.png` (train in capture),
`docs/shots/NN-capture-stealth.png` (train absent from capture).

### Result

- _pending — `--stealth` is epic #10 feature work; the capture-visible
  half can be checked today with `scripts/shot`._

---

## 5. `sl` during Zoom / Dock auto-hide

Two hostile-desktop conditions: a hidden Dock (which still owns screen
real estate at `.screenSaver`-adjacent levels) and Zoom (screen sharing,
fullscreen meeting UI, and its own overlay windows).

### Steps

1. Dock auto-hide: System Settings → Desktop & Dock → **Automatically
   hide and show the Dock** on. Move the pointer to the screen edge to
   summon the Dock, then start a held run: `scripts/run --freeze 300`.
2. While the train crosses, summon the Dock (push the pointer into the
   edge) and let it overlap the lane.
3. Zoom: join or start a meeting (`open -a zoom.us`), share the screen if
   available, and run `scripts/run` during the call. Repeat with the Zoom
   window fullscreen.
4. Capture evidence during each condition with `scripts/shot` or
   `screencapture -x` while a held run is up.

### Expected

- The lane renders above the auto-hidden Dock in both states (hidden and
  revealed); the Dock slides under the overlay, never over it.
- During a Zoom share the train appears in the shared video (default
  capture behavior — pair with check 4 for the `--stealth` contrast).
- Zoom's own UI (floating meeting controls, screenshare banner) stays
  clickable; `sl` does not steal focus from the call.
- Exiting fullscreen Zoom / un-hiding the Dock afterwards is unaffected.

### Evidence

`docs/shots/NN-dock-hide.png`, `docs/shots/NN-zoom.png`.

### Result

- _pending — run on host with a real Zoom session._
