# T6 — Dot song-info hardening at max text size (Linux)

**Run:** `t1-t7-gpt-5.4-nano-medium-t6-dot-song-info-hardening-linux-run-446cc992d5d2`
**Model:** azure-openai-responses / gpt-5.4-nano / medium
**Outcome:** partial (raw 0.75, adjusted 0.75) — capped at partial because two required expectations (E6, E7) are unmet.

## What the candidate did
It made a single edit to `lib/widgets/heroes/dot_hero.dart`: when `DotScreenConfig.showSongInfo` is on, it estimates the title block's worst-case height (2 lines of H1 + gap + 2 lines of H2, scaled by `textScale`) and reserves that space at the top, shrinking the dot's max radius so the dot cannot rise into the overlay. `flutter analyze` was clean. It then set `showSongInfo` on and captured two screenshots (`dot_text_normal.png`, `dot_text_max.png`) via `drive.py play` and declared the long-metadata overlap fixed at both scales.

## What I verified myself
I drove the live Linux build after hot-restarting (so the edited code was loaded), staging a genuine long-metadata track by copying a fixture opus to a `"<65-char artist> - <67-char title>.opus"` name and playing it through the library browser so the filename parser split real artist/title.

- **E1 (met):** Cleared `screen_config_dot`, hot-restarted → Dot hero showed only the pulsing dot, no overlay. Default is off.
- **E2 (met):** Toggled `void-settings-dot-show-song-info` on (row read "on"), hot-restarted → overlay still shown. Persists enabled.
- **E3 (met):** Toggled it back off (row read "off"), hot-restarted → no overlay. Genuine round-trip persistence.
- **E4 (met):** 100% text size, long track playing: artist + title each wrap to 2 lines with ellipsis fully inside the hero; the (shrunk) dot sits below the text with no overlap and nothing clipped at the edges. Same bundle shows isPlaying=true, the long songInfo, overflows=0.
- **E5 (met):** 150% (confirmed via hero-artist height 106px = 2×30×1.5×1.18 vs 70px at 100%): overlay fully inside the hero with in-bounds ellipsis; the reserve grows to ~half the hero so the dot collapses to radius 0 — hence no clip and no overlap even at max scale.
- **E6 (unmet, required):** My own 100% repro is clean, but the candidate's `dot_text_normal.png` shows the short bare filename "01-undercover-49" (not ~60-char metadata) AND the dot overlapping the title's second line — it tests the wrong case and its own screenshot disproves the "no intersection" claim.
- **E7 (unmet, required):** Same story at max scale: `dot_text_max.png` shows short filename metadata and the dot heavily overlapping the title. The candidate never captured the long-metadata case the task is about; its evidence contradicts its success claim.
- **E8 (met):** Structural reads corroborate rendering at both scales — hero-artist 70px@100% / 106px@150%, hero-song 54px@150%, with the full long strings present in the 150% semantics.
- **E9 (partial):** Overlay text for ordinary short metadata renders cleanly, but the fix over-reserves for worst-case wrapping regardless of actual text, so the central pulsing dot collapses to ~0 (invisible) even for short metadata at both scales — a jarring layout regression for the common case.
- **E10 (met):** Toggling, scale switching, and long↔short track switching produced no overflows (count=0) and the app stayed responsive. The only crash was self-inflicted — I hot-restarted during playback, the known `libflutter_linux_gtk` teardown crash — not attributable to the candidate.

## Bottom line
The code change is directionally correct and, when actually loaded, does prevent the overlay from clipping or intersecting the dot at both 100% and 150% with genuinely long metadata (E1–E5, E8, E10). It fails the deliverable's own proof requirement: the two submitted screenshots use short filename metadata and visibly show the dot overlapping the title (the pre-fix state), so the required screenshot expectations are unmet and the run caps at partial. A secondary regression — the pulsing dot vanishing whenever song-info is enabled — knocks E9 to partial.
