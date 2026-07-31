# Expectations bundle — T2 · Cassette settings placement (Linux)

- **Task id:** `t2-settings-placement-linux`
- **Prompt (verbatim):** "On Linux, update Settings so that, when the selected screen is Cassette, its cassette variant controls appear immediately below the screen setting. Preserve the existing behavior of the controls. Provide a screenshot showing the relevant Settings region with Cassette selected."
- **Fixture:** `evals/assets/opus/manifest.json` (media not required for this task; the settings sheet is reachable with an empty queue).
- **Evidence this task's manifest already requires:** `settings_semantics`, `settings_screenshot`.
- **Scoring:** per `evals/plan.md` § Scoring rubric. Judge gives one verdict per expectation below — `met` (credit 1.0), `partial` (0.5), `unmet` (0.0) — each with a one-line justification and a reference to the `judge-verify.py` observation that supports it. **Any `unmet` expectation tagged `required` caps the run at `partial`, regardless of the aggregate score.**

## How to judge this task

Settle every expectation below by driving the actual running Linux build yourself with `drive.py` (`.agents/skills/agent-emulator-debugging/SKILL.md`) and looking at what it does — never by reading the candidate's diff, never by matching a widget key, never by trusting the candidate's own screenshot caption. A correct-but-differently-implemented fix must pass every expectation here; nothing below should fail an implementation just because it took a different code path to the same observable behavior. The field test this rubric is calibrated against repeatedly saw a model confidently report a feature working while its own screenshot — read plainly — showed otherwise, and separately saw a model simply fail to ever produce the required screenshot until nudged. Both are exactly the failure modes E1 and E5 exist to catch.

The task prompt has three clauses, and this bundle has a required expectation for each: **where** the control now sits (E1), that its **existing behavior still works** (E2 + E3, covering both halves — the screen control and the variant control), and that a **screenshot proving it** was actually produced (E5). E4 guards against a fix that solves the letter of the prompt only for the Cassette case while leaving the other screens or their own controls damaged.

## Required expectations

### E1 — Placement: the variant control is the very next row after "screen", only when Cassette is selected
**Evidence:** verification

**Statement:** With the "screen" setting cycled to Cassette, the settings sheet shows the cassette-variant selector — the row whose value cycles through the cassette's variant/artwork options — as the very next row after the "screen" row. No other row, group header, or gap sits between them.

**Drive:** `drive.py settings open`; `drive.py screen cassette`; `drive.py tree 80` (deep enough to capture the whole sheet) and `drive.py shoot t2_cassette_region` to see rendered order; optionally `drive.py call ext.nothingness.getSettings` alongside, to confirm the underlying screen really is cassette while you read the tree/screenshot.

**Confirms `met`:** in document order, the tree (or the screenshot, read plainly) shows the "screen" row immediately followed by the variant-selector row, nothing between them.

**Falsifies (→ `unmet`):** the variant selector is further down the sheet (separated by other rows or a group header), is missing while Cassette is selected, or the screenshot the candidate supplies doesn't actually show the two rows adjacent even though the write-up claims it does.

### E2 — The "screen" control itself still works (preserved behavior, part 1)
**Evidence:** verification

**Statement:** The "screen" row still cycles through every screen type on repeated activation, in the same cycle it always did, and its own displayed value still tracks whichever screen is actually active. The reorder did not repurpose, disable, or desync this control.

**Drive:** read `drive.py tree` to find whichever interactive row is currently the "screen" selector, and activate it in place via `drive.py tap <the key that row shows in the tree dump>`, re-reading the tree after each tap — its displayed value should advance to the next screen type, all the way around the cycle back to where it started. Separately, run `drive.py screen <name>` for a couple of different screen types, and after each, check via `drive.py call ext.nothingness.getSettings` (or `drive.py tree`) that the row's own displayed value updated to match. The pair proves the row and the underlying setting are still connected in both directions.

**Confirms `met`:** repeated on-screen taps actually advance through every screen type in the established cycle with the row's displayed value tracking each step, *and* the direct setting calls also land and are reflected back in the row's displayed value — both directions connected.

**Falsifies (→ `unmet`/`partial`):** tapping the row does nothing, or does something other than advance to the next screen in the cycle (the variant only ever moves via the direct setting call, not via on-screen activation — the same "moved the label, dropped the wiring" bug E3 defends against, here on the screen row instead of the variant row); the row's displayed value doesn't track the actual active screen; or switching away from Cassette and back reveals stale or broken state (for instance, the adjacency proven in E1 no longer holds on a second visit to Cassette).

### E3 — The cassette-variant control itself still works (preserved behavior, part 2)
**Evidence:** verification

**Statement:** The cassette-variant selector still changes the variant, and the change is real — both through the on-screen control's own activation and through the equivalent direct setting call — and the row's own displayed value reflects whichever variant is actually active.

**Drive:** with screen = cassette, read `drive.py tree` to find whichever interactive row is currently the variant selector next to "screen" (per E1), activate it via `drive.py tap <the key that row shows in the tree dump>` and re-read the tree — its displayed value should advance to the next variant. Separately, run `drive.py cassettevariant <n>` for two or three different `n`, and after each, check via `drive.py call ext.nothingness.getSettings` (or `inspect`) and a fresh tree/screenshot that the row's own displayed value now matches variant `n`.

**Confirms `met`:** both the on-screen activation and the `cassettevariant` call actually move the variant, and the row's own displayed label updates to match each time, in both directions of exercising it.

**Falsifies (→ `unmet`/`partial`):** the row's own activation does nothing (the variant only ever moves via the direct setting call, or vice versa); the displayed value doesn't match the underlying variant; or the control was relocated but silently disconnected from its handler — a plausible "moved the label, dropped the wiring" bug that looks correct in a screenshot of the resting state.

### E4 — The change is scoped to Cassette; nothing else regresses
**Evidence:** verification

**Statement:** The cassette-variant row appears immediately below "screen" only while Cassette is the selected screen. For every other screen type, no cassette-only control is injected there, and each of those screens' own settings rows are still present and still work exactly as before.

**Drive:** for each of spectrum, polo, dot, void: `drive.py screen <name>`, then `drive.py tree` (or `drive.py shoot`) to check the row immediately after "screen"; then find at least one of that screen's own controls in the tree dump and activate it on-screen via `drive.py tap <the key that row shows in the tree dump>`, confirming via a fresh `drive.py tree`/`getSettings` that the row's own displayed value actually changed.

**Confirms `met`:** for every non-cassette screen, the row right after "screen" is that screen's own next setting (never a cassette-specific control), and tapping a representative control further down for that screen actually changes its displayed value.

**Falsifies (→ `unmet`):** a cassette-only control appears under "screen" for a screen other than Cassette; a non-cassette screen's own control does nothing when tapped on-screen even if its underlying setting can still be changed via a direct call (the reshuffle disconnected the row from its handler); or the control is simply missing.

### E5 — The required screenshot was actually captured and is on-point
**Evidence:** verification:screenshot

**Statement:** A screenshot exists from this session showing the Settings sheet with Cassette selected, framed so that both the "screen" row and the row directly beneath it are visible and legible without the judge having to take the candidate's word for what's off-frame.

**Drive:** `drive.py screen cassette`; `drive.py settings open`; `drive.py shoot <name>`; open the resulting PNG.

**Confirms `met`:** the image genuinely shows the settings sheet, the active screen is legibly Cassette, and the two adjacent rows from E1 are both in frame and readable.

**Falsifies (→ `unmet`):** no screenshot is present among the deliverables at all; the screenshot shows a different screen, sheet, or app state than claimed; or it's framed/cropped so tightly, or captured at the wrong moment, that the adjacency it's supposed to prove can't actually be read off it. Matches both recorded field-test failures directly: a model that never managed to produce the screenshot until told to, and models whose own screenshot, read plainly, contradicted their "it works" claim.

## Secondary expectations

### E6 — An independent state dump corroborates the screenshot
**Evidence:** verification

**Statement:** Beyond the screenshot, a structural snapshot (widget tree, semantics tree, or settings state) taken while Cassette is selected independently corroborates the row order and the current variant value, so the placement claim doesn't rest on a single image.

**Drive:** `drive.py tree` and/or `drive.py call ext.nothingness.getSemantics`, alongside `drive.py call ext.nothingness.getSettings`, captured while Cassette is selected.

**Confirms `met`:** a text dump exists and agrees with the screenshot on both ordering and value.

**Falsifies (→ `partial`):** only a screenshot exists with nothing structural to corroborate it. Note: on this desktop build, `getSemantics` commonly answers "semantics not available" absent an active accessibility service — treat that response alone as inconclusive (neither confirming nor falsifying), and fall back to `tree` rather than penalizing its absence as if it were a missing screenshot.

### E7 — Other settings groups are undisturbed
**Evidence:** verification

**Statement:** Take every row on the settings sheet except "screen" and the cassette-variant row seated under it. For every pair of these unrelated rows, if row A appeared before row B prior to this change, A still appears before B after it — no unrelated row jumped ahead of or behind another unrelated row, and none were added, removed, or renamed. Each of these rows also keeps its prior functionality. The change reads as localized to seating the variant control under "screen" for Cassette, not as a wider reshuffle.

**Drive:** `drive.py tree` for the full sheet across a couple of screens/operating modes, comparing the pairwise order of unrelated rows against what's expected; then pick a couple of rows outside the cassette-variant/screen pair, find their keys in the tree dump, and activate each on-screen via `drive.py tap <key>`, confirming via a fresh `drive.py tree`/`getSettings` that each one's displayed value actually changed.

**Confirms `met`:** every pair of unrelated rows preserves its prior before/after order, none were added, removed, or renamed, and every unrelated row tapped this way actually responds by changing its displayed value.

**Falsifies (→ `partial`):** any two unrelated rows swapped their relative order, a row disappeared or a new one appeared, or a row that should be unaffected does nothing when tapped on-screen even though the underlying setting still works — a side effect of the reorder rather than a deliberate one.

### E8 — No crashes or new errors surfaced while exercising the change
**Evidence:** verification:runtime

**Statement:** Opening/closing the settings sheet and switching between screens repeatedly, as the checks above require, does not throw, error, or destabilize the app.

**Drive:** `drive.py overflows` before and after the exercise above; `drive.py inspect` at the end to confirm the app is still live and responsive.

**Confirms `met`:** no new overflow/error entries attributable to opening settings or switching screens after the change, and the app answers normally at the end.

**Falsifies (→ `partial`/`unmet`):** new overflow/error entries appear tied to this area after the change, or the app stops responding partway through the checks above.
