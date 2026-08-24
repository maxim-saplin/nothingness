# Judge notes — T6 Dot song-info hardening (Linux)

**Run:** `t1-t7-gpt-5.4-nano-low-t6-dot-song-info-hardening-linux-run-3e023fcdc78e`
**Model:** gpt-5.4-nano (thinking low) · **Outcome:** partial · **Score:** 1/3

## What the candidate actually did
- 16 tool calls total (34 bash, 12 read, 4 edit). It edited **only** `lib/widgets/heroes/dot_hero.dart`
  (git: `1 file changed, 64 insertions(+), 18 deletions(-)`).
- The change wraps the centered pulsing dot in a `Transform.translate(0, shiftDown)` that is supposed to
  nudge the dot **down** far enough to clear the top-pinned `HeroTitleBlock` overlay when
  `config.showSongInfo` is on. `shiftDown` is computed from an estimated 2-line overlay height and then
  **clamped so the dot stays inside the hero**.
- It ran `flutter analyze` (clean) and stopped. **It never launched the app and produced no screenshots** —
  it explicitly said so in its final message ("I wasn't able to generate the required PNG screenshots … the
  harness/driver … isn't available"). The prompt explicitly requires screenshots at both scales.

## Why the fix does not work (verified live)
At the real Dot-hero dimensions the hero band is short (~228px tall) while the dot radius grows to
`min(maxDotSize=120, min(w,h)/2) ≈ 114` — i.e. the dot already fills the hero vertically. The candidate's
clamp `(maxHeight-4) - (center+radius)` evaluates **negative**, so `shiftDown` collapses to **0**. The dot
therefore stays centered and continues to overlap the top-pinned overlay — the exact bug the task exists to
fix. Confirmed by driving the live Linux build with a staged long-metadata track (artist 77 chars, title 89
chars, resolved via the library-browser filename parser).

## Per-expectation findings (all settled by live reproduction)
- **E1 (met)** — `clearpref *` + hot restart: with the long track playing, the hero shows only the pulsing
  dot, no overlay, and the settings row reads "show song info / off". Default-off preserved.
- **E2 (met)** — toggled on (row "on"), hot restart, row still "on"; replaying the track shows the overlay
  without re-toggling. Setting genuinely persists.
- **E3 (met)** — toggled back off, hot restart, row still "off", no overlay with a track playing. Round-trip
  persistence intact.
- **E4 (unmet, required)** — 100% + long metadata: screenshot shows the dot drawn **on top of** the overlay
  ("The Extraordina●rbose Symphonic", "of N●eaches"). Overlay pixels share the dot's region and are occluded.
- **E5 (unmet, required)** — 150% (slider confirmed reading "150%") + long metadata: the dot massively
  overlaps every overlay line. This is the single most important observation and it fails.
- **E6 (unmet, required)** — no candidate normal-scale screenshot exists; my own 100% repro shows overlap.
- **E7 (unmet, required)** — no candidate max-scale screenshot exists; my own 150% repro shows overlap.
- **E8 (met, secondary)** — getSemantics at 100% and 150% both contain the full artist/title text as rendered
  hero nodes — structural corroboration that text renders.
- **E9 (partial, secondary)** — short metadata ("undercover"/"53") also overlaps the dot at both scales
  ("und●ver"). This matches the pre-change layout (the fix is a no-op), so it is not a *new* regression, but
  the common case still doesn't render cleanly.
- **E10 (met, secondary)** — after toggling, scale-switching and long/short track swaps, `overflows` = 0 and
  `inspect` answered normally (live, screen=dot, playing).

## Environment notes (not charged to candidate)
- One hot-restart-during-playback tore down the app ("Lost connection to device", core.1819 dump). No
  "Callback invoked after it has been deleted" signature — this is the documented harness fragility, not a
  candidate defect. I paused before subsequent restarts and the app was stable.
- Long metadata was staged by copying a fixture opus to `"<long artist> - <long title>.opus"` and tapping its
  `void-file:` browser row (the filename parser splits artist/title); `drive.py play` alone yields no artist.
- 150% was set via `setPreference screen_config_dot` (textScale 1.5) + hot restart; the text-size slider row
  was then confirmed reading "150%" via an XTEST wheel scroll of the settings sheet.
