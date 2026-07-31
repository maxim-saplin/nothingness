# Expectations bundle — T6 · Harden Dot song information at maximum text size (Linux)

- **Task id:** `t6-dot-song-info-hardening-linux`
- **Prompt (verbatim):** "On Linux, preserve Dot's default-off persistent show-song-info option. With long artist and title metadata at normal and maximum text size, information must remain visible inside the hero without clipping or intersecting the centered pulsing dot. Provide screenshots at both scales."
- **Fixture:** `evals/assets/opus/manifest.json` — 10 tracks mounted at `/opt/nothingness/media` in the candidate's container. None of the ten carries genuinely long artist/title tags, so the candidate (and you, reproducing) need a track with deliberately long metadata — e.g. a copy of one fixture retagged, or played under a path/name long enough to surface as long metadata, however the app resolves it.
- **Evidence this task's manifest already requires:** `fresh_default`, `persisted_enabled`, `normal_geometry`, `max_geometry`, `normal_screenshot`, `max_screenshot`, `disabled_state`.
- **Scoring:** per `evals/README.md` § Scoring rubric. Judge gives one verdict per expectation below — `met` (credit 1.0), `partial` (0.5), `unmet` (0.0) — each with a one-line justification and a reference to the `judge-verify.py` observation that supports it. **Any `unmet` expectation tagged `required` caps the run at `partial`, regardless of the aggregate score.**

## How to judge this task

Dot's "show song info" option already exists, defaults off, and already persists. This task is a hardening task, not a from-scratch feature: the prompt asks that the *existing* option keep behaving exactly as it does (default off, persists when toggled) while the overlay it displays is made robust against long metadata at the largest available text size — a scale at which the overlay can plausibly grow tall enough to clip or visually collide with the centered pulsing dot beneath it. Settle every expectation by driving the real Linux build; "long enough to matter" means at least ~60 characters each for artist and title — short enough that a lazy fix wouldn't need to handle it, long enough that at 150% text size it visibly exercises multi-line wrapping.

"Maximum text size" refers to the per-Dot-screen text-size control in Settings (a 50%–150% range) at its top end, not the OS/system font-scale setting.

## Required expectations

### E1 — Fresh default is off
**Evidence:** verification

**Statement:** On a fresh app state with no prior preference set for this option, the Dot hero shows no artist/title overlay at all — the option's default is off, exactly as before this change.

**Drive:** `drive.py clearpref *` (or the specific preference key(s) backing this option, if narrower clearing is available) followed by `drive.py restart`; `drive.py screen dot`; `drive.py tree`/`drive.py shoot` to confirm no song-info overlay is present over the dot.

**Confirms `met`:** with preferences cleared and the app restarted, the Dot hero shows the pulsing dot alone, no artist/title text overlay.

**Falsifies (→ `unmet`):** the overlay appears despite a cleared/fresh preference state, or the option can't actually be confirmed off from a genuinely fresh state.

### E2 — Enabling the option persists across a restart
**Evidence:** verification

**Statement:** Turning the option on and restarting the app (not merely leaving it running) keeps it on — the setting is genuinely persisted, not just held in memory for the current session.

**Drive:** `drive.py screen dot`; `drive.py settings open`; find and activate the "show song info" toggle via `drive.py tap <key from tree>`; confirm it reads on; `drive.py restart` (hot restart re-initializes app state from the same persisted store; if in doubt, prefer a full process relaunch per the agent-emulator-debugging skill's isolated Linux launch recipe); `drive.py screen dot`; `drive.py tree`/`drive.py shoot` to confirm the overlay is still showing.

**Confirms `met`:** after the restart, the Dot hero still shows the song-info overlay without re-toggling it.

**Falsifies (→ `unmet`):** the option reverts to off after a restart, or the toggle's on-screen state and the actual rendered overlay disagree.

### E3 — Disabling the option also persists (round trip)
**Evidence:** verification

**Statement:** Turning the option back off and restarting keeps it off — the persistence is a genuine round trip, not a one-way "sticks on" bug.

**Drive:** from the enabled state in E2, toggle the "show song info" control off; `drive.py restart`; `drive.py screen dot`; `drive.py tree`/`drive.py shoot`.

**Confirms `met`:** after the restart, the Dot hero shows no overlay, matching the disabled state chosen before the restart.

**Falsifies (→ `unmet`):** the overlay reappears after restart despite having been explicitly disabled beforehand.

### E4 — At normal text size, long metadata stays inside the hero without clipping or touching the dot
**Evidence:** verification:screenshot

**Statement:** With the song-info option on, the text-size control at its default/normal setting (100%), and a track whose artist and title are each at least ~60 characters, the overlay text is fully contained within the hero's visible bounds and does not visually overlap the pulsing dot's current extent. This is a pixel-level visual judgment — a tree, semantics, or settings dump cannot settle it (`getWidgetTree` has no reliable absolute geometry and `probeText` returns text/style but no position), so a genuine screenshot is the only evidence that can.

**Drive:** enable the option; set the Dot text-size control to 100% (its default) via the settings sheet; `drive.py play <the long-metadata track>`; `drive.py screen dot`; `drive.py shoot t6_normal`; open the PNG and visually inspect it at full resolution (zoom in if needed to check edges precisely): does any part of the overlay's rendered pixels fall outside the hero's own visible bounds (top/bottom/side), and does any part of the overlay's rendered pixels occupy the same screen region as the dot's currently-pulsing circle (including any glow/halo that is visually part of the pulsing shape, not just its solid core).

**Confirms `met`:** the screenshot shows the full overlay (however it wraps/truncates by design) with none of its rendered pixels occupying the same screen region as the dot's pulsing shape, and none of its rendered pixels falling outside the hero's own visible bounds (an intentional, legible truncation such as an ellipsis rendered fully inside the hero is not a clip; a glyph cut in half at the hero's edge, or text continuing past the hero boundary, is).

**Falsifies (→ `unmet`):** any part of the overlay's rendered pixels visibly occupies the same screen region as the dot's pulsing shape (including its glow, if the dot has one), or any part of the overlay text is visibly cut off at the hero's own top/bottom/side edges rather than legibly truncated within them.

### E5 — At maximum text size, long metadata stays inside the hero without clipping or touching the dot
**Evidence:** verification:screenshot

**Statement:** With the same long-metadata track and the song-info option on, moving the Dot text-size control to its maximum (150%) still keeps the overlay fully contained within the hero and non-overlapping with the dot — the scenario the prompt is specifically hardening against. Like E4, this is a pixel-level visual judgment settleable only by a genuine screenshot, never by a tree/semantics/settings dump.

**Drive:** with the option on and the long-metadata track playing, move the Dot screen's text-size control to 150% via the settings sheet (drive it however reliably reproduces the change; confirm the row's own displayed value reads "150%" before proceeding); `drive.py screen dot`; `drive.py shoot t6_max`; open the PNG and inspect for clipping/overlap using the exact same pixel-region criteria as E4, at the larger scale.

**Confirms `met`:** the screenshot shows the overlay fully within the hero's own visible bounds (no pixels cut off at an edge) with none of its rendered pixels occupying the same screen region as the dot's pulsing shape, even at 150% text size.

**Falsifies (→ `unmet`):** the screenshot shows any part of the overlay's rendered pixels occupying the same screen region as the dot's pulsing shape, or any part of the overlay text cut off at the hero's own bounds at 150% — this is the specific regression the task exists to fix, so treat it as the single most important observation in this bundle.

### E6 — The required normal-scale screenshot was actually captured and is on-point
**Evidence:** verification:screenshot

**Statement:** A screenshot exists from this session, taken at 100% text size with the long-metadata track playing and the option on, and it genuinely supports the "no clipping, no overlap" claim rather than merely existing. Unlike T4's mid-gesture case, this state is not time-sensitive — reproduce it yourself, right now, rather than resting the verdict only on the candidate's own submission.

**Drive:** reproduce E4's setup yourself (option on, 100% text size, the long-metadata track playing) and `drive.py shoot` your own fresh copy — this is the citable evidence for this expectation. Then review the candidate's submitted normal-scale screenshot side by side with your own, both against the criteria in E4.

**Confirms `met`:** your own fresh reproduction, read plainly, shows no clipping or dot overlap per E4's criteria, and the candidate's submitted screenshot (legibly at 100% scale, showing the long metadata) agrees with it.

**Falsifies (→ `unmet`):** no candidate screenshot exists among the deliverables; it's actually captured at a different scale than claimed; the metadata shown isn't actually long; or either your own reproduction or the candidate's screenshot shows clipping/overlap that the write-up doesn't acknowledge.

### E7 — The required max-scale screenshot was actually captured and is on-point
**Evidence:** verification:screenshot

**Statement:** A screenshot exists from this session, taken at 150% text size with the long-metadata track playing and the option on, and it genuinely supports the "no clipping, no overlap" claim. Like E6, this state is fully reproducible on demand — verify it live, don't take the submission on faith.

**Drive:** reproduce E5's setup yourself (option on, 150% text size, the long-metadata track playing) and `drive.py shoot` your own fresh copy — this is the citable evidence for this expectation. Then review the candidate's submitted max-scale screenshot side by side with your own, both against the criteria in E5.

**Confirms `met`:** your own fresh reproduction, read plainly, shows no clipping or dot overlap per E5's criteria, and the candidate's submitted screenshot (legibly at 150% scale, showing the long metadata) agrees with it.

**Falsifies (→ `unmet`):** no candidate screenshot exists among the deliverables; it's actually captured at a different scale than claimed (e.g. still 100%, mislabeled); the metadata shown isn't actually long; or either your own reproduction or the candidate's screenshot shows clipping/overlap the write-up glosses over — the exact "declared success, screenshot disproves it" failure this whole rubric family is calibrated against.

## Secondary expectations

### E8 — Independent geometry corroborates the screenshots
**Evidence:** verification

**Statement:** Beyond the two screenshots, some structural read (`drive.py probe <a key inside the overlay>`, `drive.py tree`, or the equivalent) at both scales independently corroborates that the overlay text is genuinely rendering (non-zero size, non-empty resolved text) rather than resting the whole claim on two images.

**Drive:** `drive.py probe <key>` for the overlay's rendered text at 100% and again at 150%, alongside the corresponding `tree` dump.

**Confirms `met`:** a structural read exists at both scales showing non-empty, non-zero-size text consistent with the screenshots.

**Falsifies (→ `partial`):** only screenshots exist with nothing structural corroborating either scale.

### E9 — Short/typical metadata is unaffected
**Evidence:** verification

**Statement:** For a track with ordinary short metadata (any of the ten supplied fixtures), the song-info overlay at both text scales looks the same as it did before this hardening change — no new spacing, truncation, or layout regression was introduced for the common case while fixing the long-metadata edge case.

**Drive:** with the option on, `drive.py play <one of the ten fixtures>`; `drive.py screen dot`; `drive.py shoot` at 100% and 150% text size; visually compare against E4/E5's captures for layout consistency (position, spacing) beyond just the text length.

**Confirms `met`:** the overlay for ordinary metadata renders cleanly at both scales, with no clipping or dot overlap and no obviously different spacing/positioning versus what a reasonable unmodified rendering would look like.

**Falsifies (→ `partial`):** the ordinary-metadata case now also clips, overlaps the dot, or shows a jarring layout regression introduced by the fix.

### E10 — No crashes or new errors surfaced while exercising the change
**Evidence:** verification:runtime

**Statement:** Toggling the option, switching text scales, and switching between long- and short-metadata tracks repeatedly does not throw, error, or destabilize the app.

**Drive:** `drive.py overflows` before and after the exercise above; `drive.py inspect` at the end to confirm the app is still live and responsive.

**Confirms `met`:** no new overflow/error entries attributable to this area, and the app answers normally at the end.

**Falsifies (→ `partial`/`unmet`):** new overflow/error entries appear tied to this area, or the app stops responding partway through the checks above.
