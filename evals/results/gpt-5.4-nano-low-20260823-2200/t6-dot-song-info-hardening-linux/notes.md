# t6-dot-song-info-hardening-linux — judge notes

**Run:** t1-t7-gpt-5.4-nano-low-t6-dot-song-info-hardening-linux-run-40334feff028
**Model:** azure-openai-responses / gpt-5.4-nano / low
**Outcome:** partial (score 1). Required E4–E7 unmet cap the run.

## What the candidate did
It edited only `lib/widgets/heroes/dot_hero.dart` (+12/-1), ran `flutter analyze` (clean), and never
launched the app — its own `drive.py` verification failed to find a VM service, and it delivered **no
screenshots** (its final message asked how to generate them). The change reserves vertical space at the
top of the hero for the song-info overlay and clamps the pulsing dot's radius so the dot's top edge
can't reach that reserved region:
`maxAllowed = min(min(w,h)/2, centerY - textReservedBottom)`, then `r.clamp(minDotSize, min(maxDotSize, maxAllowed))`.

## The decisive defect (found by driving the real Linux build)
The Dot hero band on this layout is only ~225 px tall, so `centerY ≈ 110`. With the option on,
`textReservedBottom` (a fixed 2-line estimate) is ~126 at 100% and larger at 150%, so
`maxDotFromTop = centerY - textReservedBottom` goes negative and clamps to 0. `_radiusFor` then calls
`r.clamp(20.0, min(120, 0)=0)` — lower limit 20 > upper limit 0 — which throws
`ArgumentError: Invalid argument(s): 20.0` on **every spectrum frame**. The dot subtree is replaced by
Flutter's red error box that fills the hero, with the overlay text painted over it. This fires whenever
the option is enabled, independent of metadata length or text scale. When the option is off the dot
renders perfectly (E1). Base code (without this diff) does not crash. Note: `drive.py overflows` reads 0
because this caught widget-build exception never lands in the overflow ring buffer — the run log and
screenshots are the real evidence.

## Per-expectation
- **E1 (met):** Prefs cleared + hot restart, a track playing (isPlaying true, songInfo present), Dot hero
  shows the pulsing dot alone, no overlay. Default off preserved; dot renders cleanly.
- **E2 (met):** Toggled on (read "on"), hot restart without re-toggling, overlay title persisted
  (probe hero-song returned the title). Persistence works. (The dot crash is scored under E4/E5/E10.)
- **E3 (met):** Toggled off, hot restart, track playing, hero-song widget absent. Genuine round trip.
- **E4 (unmet):** 100% + long metadata (artist 66 ch, title 65 ch): dot crashes into the red error box;
  overlay sits over it. Not a clean contained overlay.
- **E5 (unmet):** Slider driven to a confirmed 150% (XTEST): identical crash, artist H1 ellipsized,
  overlay over the error box. This is the exact regression the task targets.
- **E6 (unmet):** No candidate normal-scale screenshot delivered; my own 100% reproduction shows the crash.
- **E7 (unmet):** No candidate max-scale screenshot delivered; my own 150% reproduction shows the crash.
- **E8 (met):** Overlay text genuinely renders at both scales — probe/tree: artist 30px→45px, song
  15px→22.5px, non-zero sizes. (Only the dot fails.)
- **E9 (partial):** Common case regressed — short fixture with the option on also crashes at 100% and 150%.
- **E10 (unmet):** Continuous ArgumentError stream tied directly to this change; app still answers inspect
  but the dot renders as an error box.

## How I verified
Launched the real Linux debug build in-container (Xvfb :99), drove it via `drive.py`, staged a long-metadata
opus (`"<66-char artist> - <65-char title>.opus"`) and played it through the library browser so the filename
parser resolved both fields, toggled the option and hot-restarted for the persistence trio, and drove the
text-size slider to a confirmed 150% via real XTEST input. Screenshots captured through `judge-verify.py`;
runtime/git via `judge-inspect.py`.
