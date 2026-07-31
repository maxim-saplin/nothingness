# Expectations bundle — T3 · Cassette settings placement + color-scheme rename (Linux)

- **Task id:** `t3-settings-placement-color-scheme-linux`
- **Prompt (verbatim):** "On Linux, update Settings so that, when the selected screen is Cassette, its cassette variant controls appear immediately below the screen setting. Rename the color-changing cassette variant setting to exactly `color scheme`. Preserve the existing behavior of the controls. Provide a screenshot showing the relevant Settings region with Cassette selected."
- **Fixture:** `evals/assets/opus/manifest.json` (media not required for this task; the settings sheet is reachable with an empty queue).
- **Evidence this task's manifest already requires:** `settings_semantics`, `settings_screenshot`.
- **Scoring:** per `evals/README.md` § Scoring rubric. Judge gives one verdict per expectation below — `met` (credit 1.0), `partial` (0.5), `unmet` (0.0) — each with a one-line justification and a reference to the `judge-verify.py` observation that supports it. **Any `unmet` expectation tagged `required` caps the run at `partial`, regardless of the aggregate score.**

## How to judge this task

This task is T2 plus one clause: the same reorder, plus renaming the variant-cycling control's label to exactly `color scheme`. Settle every expectation below by driving the actual running Linux build yourself with `drive.py` and looking at what it does — never by reading the candidate's diff, never by matching a widget key, never by trusting the candidate's own screenshot caption. A correct-but-differently-implemented fix must pass every expectation here.

The prompt has four clauses, and this bundle has a required expectation tracing to each: **where** the control sits (E1), that it is **renamed to exactly the requested string** (E2), that its **existing behavior still works** (E3 + E4, covering both the screen control and the renamed control), and that a **screenshot proving it** was produced (E6). E5 guards against a fix that solves the letter of the prompt only for Cassette while damaging other screens. The field test this rubric family is calibrated against repeatedly saw a model confidently report a feature working while its own screenshot, read plainly, showed otherwise — and separately saw a model simply fail to produce the required screenshot until nudged. Both are exactly the failure modes E2 and E6 exist to catch.

## Required expectations

### E1 — Placement: the renamed control is the very next row after "screen", only when Cassette is selected
**Evidence:** verification

**Statement:** With the "screen" setting cycled to Cassette, the settings sheet shows the cassette-variant-cycling control (whichever row's value cycles through the cassette's variant/artwork options, whatever its label reads) as the very next row after the "screen" row. No other row, group header, or gap sits between them.

**Drive:** `drive.py settings open`; `drive.py screen cassette`; `drive.py tree 80` and `drive.py shoot t3_cassette_region` to see rendered order; optionally `drive.py call ext.nothingness.getSettings` alongside to confirm the underlying screen really is cassette while reading the tree/screenshot.

**Confirms `met`:** in document order, the tree (or the screenshot, read plainly) shows the "screen" row immediately followed by the variant-cycling row, nothing between them.

**Falsifies (→ `unmet`):** the variant-cycling control is further down the sheet, is missing while Cassette is selected, or the screenshot the candidate supplies doesn't actually show the two rows adjacent even though the write-up claims it does.

### E2 — The control's label reads exactly "color scheme"
**Evidence:** verification

**Statement:** The label text of the row identified in E1 reads exactly `color scheme` — the literal string from the prompt, in the same lowercase register every other row label in this sheet uses (e.g. "theme", "variant", "text size") — not "Color Scheme", not "colour scheme", not left as "variant", and not a second, duplicate row added alongside an unrenamed original.

**Drive:** with the same tree/screenshot from E1, read the row's label text character-for-character; separately scan the rest of the sheet (`drive.py tree 80` across a full scroll) to confirm no leftover row still labeled "variant" exists anywhere.

**Confirms `met`:** the row's label reads exactly `color scheme` and there is exactly one such row — no duplicate, no stale "variant" row left behind.

**Falsifies (→ `unmet`):** the label is missing, differs in case or wording from `color scheme`, still reads "variant", or a second row was added under the new name while the original labeled row remains elsewhere in the sheet.

### E3 — The "screen" control itself still works (preserved behavior, part 1)
**Evidence:** verification

**Statement:** The "screen" row still cycles through every screen type on repeated activation, in the same cycle it always did, and its own displayed value still tracks whichever screen is actually active. The reorder and rename did not repurpose, disable, or desync this control.

**Drive:** read `drive.py tree` to find whichever interactive row is currently the "screen" selector, and activate it in place via `drive.py tap <the key that row shows in the tree dump>`, re-reading the tree after each tap — its displayed value should advance to the next screen type, all the way around the cycle back to where it started. Separately, run `drive.py screen <name>` for a couple of different screen types, and after each, check via `drive.py call ext.nothingness.getSettings` (or `drive.py tree`) that the row's own displayed value updated to match.

**Confirms `met`:** repeated on-screen taps actually advance through every screen type in the established cycle with the row's displayed value tracking each step, *and* the direct setting calls also land and are reflected back in the row's displayed value.

**Falsifies (→ `unmet`/`partial`):** tapping the row does nothing or advances incorrectly; the row's displayed value doesn't track the actual active screen; or switching away from Cassette and back reveals stale or broken state (the adjacency from E1 no longer holds on a second visit).

### E4 — The renamed control itself still works (preserved behavior, part 2)
**Evidence:** verification

**Statement:** The row renamed to `color scheme` still changes the cassette's variant — both through the on-screen control's own activation and through the equivalent direct setting call — and the row's own displayed value reflects whichever variant is actually active. Renaming the label did not disconnect the control from its handler.

**Drive:** with screen = cassette, read `drive.py tree` to find the `color scheme` row, activate it via `drive.py tap <the key that row shows in the tree dump>` and re-read the tree — its displayed value should advance to the next variant. Separately, run `drive.py cassettevariant <n>` for two or three different `n`, and after each, check via `drive.py call ext.nothingness.getSettings` (or `inspect`) and a fresh tree/screenshot that the row's own displayed value now matches variant `n`.

**Confirms `met`:** both the on-screen activation and the `cassettevariant` call actually move the variant, and the row's own displayed label/value updates to match each time, in both directions of exercising it.

**Falsifies (→ `unmet`/`partial`):** the row's own activation does nothing (the variant only ever moves via the direct setting call, or vice versa); the displayed value doesn't match the underlying variant; or the control was renamed and relocated but silently disconnected from its handler — a plausible "renamed the label, dropped the wiring" bug that looks correct in a screenshot of the resting state.

### E5 — The change is scoped to Cassette; nothing else regresses
**Evidence:** verification

**Statement:** The `color scheme` row appears immediately below "screen" only while Cassette is the selected screen. For every other screen type, no cassette-only control is injected there, no row anywhere else was accidentally renamed to `color scheme`, and each of those screens' own settings rows are still present and still work exactly as before.

**Drive:** for each of spectrum, polo, dot, void: `drive.py screen <name>`, then `drive.py tree` (or `drive.py shoot`) to check the row immediately after "screen" and to scan for any stray `color scheme` label; then find at least one of that screen's own controls in the tree dump and activate it on-screen via `drive.py tap <the key that row shows in the tree dump>`, confirming via a fresh `drive.py tree`/`getSettings` that the row's own displayed value actually changed.

**Confirms `met`:** for every non-cassette screen, the row right after "screen" is that screen's own next setting (never a cassette-specific control, never a `color scheme` label), and tapping a representative control further down for that screen actually changes its displayed value.

**Falsifies (→ `unmet`):** a cassette-only control or a `color scheme`-labeled row appears under "screen" for a screen other than Cassette; a non-cassette screen's own control does nothing when tapped on-screen even if its underlying setting can still be changed via a direct call; or the control is simply missing.

### E6 — The required screenshot was actually captured and is on-point
**Evidence:** verification:screenshot

**Statement:** A screenshot exists from this session showing the Settings sheet with Cassette selected, framed so that both the "screen" row and the `color scheme` row directly beneath it are visible and legible without the judge having to take the candidate's word for what's off-frame.

**Drive:** `drive.py screen cassette`; `drive.py settings open`; `drive.py shoot <name>`; open the resulting PNG.

**Confirms `met`:** the image genuinely shows the settings sheet, the active screen is legibly Cassette, and the two adjacent rows from E1/E2 are both in frame, with the `color scheme` label readable.

**Falsifies (→ `unmet`):** no screenshot is present among the deliverables at all; the screenshot shows a different screen, sheet, or app state than claimed; or it's framed/cropped so tightly, or captured at the wrong moment, that the adjacency and the renamed label can't actually be read off it.

## Secondary expectations

### E7 — An independent state dump corroborates the screenshot
**Evidence:** verification

**Statement:** Beyond the screenshot, a structural snapshot (widget tree, semantics tree, or settings state) taken while Cassette is selected independently corroborates the row order, the exact label text, and the current variant value, so the placement and rename claims don't rest on a single image.

**Drive:** `drive.py tree` and/or `drive.py call ext.nothingness.getSemantics`, alongside `drive.py call ext.nothingness.getSettings`, captured while Cassette is selected.

**Confirms `met`:** a text dump exists and agrees with the screenshot on ordering, exact label text, and value.

**Falsifies (→ `partial`):** only a screenshot exists with nothing structural to corroborate it. Note: `getSemantics` commonly answers "semantics not available" absent an active accessibility service on this desktop build — treat that response alone as inconclusive, and fall back to `tree`.

### E8 — Other settings groups are undisturbed
**Evidence:** verification

**Statement:** Every row on the settings sheet except "screen" and the `color scheme` row seated under it keeps its prior relative order against every other unrelated row — no unrelated row jumped ahead of or behind another unrelated row, and none were added, removed, or renamed. Each of these rows also keeps its prior functionality.

**Drive:** `drive.py tree` for the full sheet across a couple of screens/operating modes, comparing the pairwise order of unrelated rows against what's expected; then pick a couple of rows outside the `color scheme`/screen pair, find their keys in the tree dump, and activate each on-screen via `drive.py tap <key>`, confirming via a fresh `drive.py tree`/`getSettings` that each one's displayed value actually changed.

**Confirms `met`:** every pair of unrelated rows preserves its prior before/after order, none were added, removed, or renamed, and every unrelated row tapped this way actually responds by changing its displayed value.

**Falsifies (→ `partial`):** any two unrelated rows swapped their relative order, a row disappeared or a new one appeared, or a row that should be unaffected does nothing when tapped on-screen even though the underlying setting still works.

### E9 — No crashes or new errors surfaced while exercising the change
**Evidence:** verification:runtime

**Statement:** Opening/closing the settings sheet, switching between screens, and cycling the `color scheme` control repeatedly, as the checks above require, does not throw, error, or destabilize the app.

**Drive:** `drive.py overflows` before and after the exercise above; `drive.py inspect` at the end to confirm the app is still live and responsive.

**Confirms `met`:** no new overflow/error entries attributable to this area after the change, and the app answers normally at the end.

**Falsifies (→ `partial`/`unmet`):** new overflow/error entries appear tied to this area after the change, or the app stops responding partway through the checks above.
