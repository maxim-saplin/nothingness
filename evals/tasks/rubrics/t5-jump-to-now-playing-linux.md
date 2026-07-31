# Expectations bundle — T5 · Jump to now playing (Linux)

- **Task id:** `t5-jump-to-now-playing-linux`
- **Prompt (verbatim):** "On Linux, add a conditional, accessible action that brings the current playing track into view when it is outside the visible browser region, including when its parent is already the current browser folder. Activation must keep the browser in that folder and make the row visible. Do not expose an active action when no track is playing. Provide before and after screenshots."
- **Fixture:** `evals/assets/opus/manifest.json` — 10 tracks mounted at `/opt/nothingness/media` in the candidate's container.
- **Evidence this task's manifest already requires:** `jump_pre_state`, `jump_action`, `jump_post_state`, `jump_before_screenshot`, `jump_after_screenshot`, `no_playing_state`.
- **Scoring:** per `evals/README.md` § Scoring rubric. Judge gives one verdict per expectation below — `met` (credit 1.0), `partial` (0.5), `unmet` (0.0) — each with a one-line justification and a reference to the `judge-verify.py` observation that supports it. **Any `unmet` expectation tagged `required` caps the run at `partial`, regardless of the aggregate score.**

## How to judge this task

A "jump to now playing" affordance already exists in some form when the playing track lives in a *different* folder than the one being browsed. The prompt's load-bearing clause — "**including when its parent is already the current browser folder**" — asks for the harder case: the playing track's folder is already open, but its row has scrolled out of view, and the action must still surface and still work, by scrolling rather than by navigating. A plausible-but-wrong fix ships only the easy (different-folder) case and never the harder one; a differently plausible-but-wrong fix shows the action unconditionally regardless of whether the row is actually out of view. Settle every expectation below by driving the real Linux build and looking at what the browser and its accessibility tree actually do — never by trusting the candidate's write-up.

To force a folder to overflow one screenful (needed for the "same folder, scrolled out of view" cases), shrink the window first, e.g. `drive.py window 400 640`, before browsing into the ten-fixture folder.

## Required expectations

### E1 — The action still works across folders (existing behavior preserved)
**Evidence:** verification

**Statement:** When the currently playing track's folder is *different* from the one currently browsed, a jump action is available; activating it navigates the browser to the playing track's folder and leaves that track's row visible on screen.

**Drive:** `drive.py play <fixture A>`; `drive.py nav <a different folder than fixture A's parent — e.g. navigate up to the mount root if the ten fixtures are flat>` (or otherwise ensure the browsed folder differs from fixture A's parent); `drive.py tree` / `drive.py call ext.nothingness.getSemantics` to find the jump action; activate it (`drive.py tap <the key/action the tree shows>`); `drive.py call ext.nothingness.getLibraryState` and a fresh `drive.py tree`/`drive.py shoot` to confirm the browser is now in fixture A's parent folder with its row visible.

**Confirms `met`:** before activation the jump action is present; after activation the browser's current folder is fixture A's parent and fixture A's row is on screen.

**Falsifies (→ `unmet`):** the action is absent in this scenario, activating it lands in the wrong folder, or the target row isn't actually visible afterward.

### E2 — The action also works when the row is merely scrolled out of view within the already-correct folder (the core hardening ask)
**Evidence:** verification

**Statement:** When the browsed folder *is already* the playing track's parent folder, but its row is scrolled outside the visible list region, the jump action is still available; activating it scrolls the existing list to reveal the row, and the browser **stays in the same folder** rather than re-navigating.

**Drive:** shrink the window (e.g. `drive.py window 400 640`) so the ten-fixture folder overflows one screenful; `drive.py nav <the fixtures' folder>`; `drive.py play <a fixture whose row, once you scroll the list away from it, is off-screen>`; scroll the folder view away from that row (e.g. re-`nav` to the folder after navigating elsewhere and back, or use whatever scroll-to-top affordance the tree exposes) so the playing row is confirmed off-screen via `drive.py tree`/`drive.py shoot`; then find and activate the jump action; `drive.py call ext.nothingness.getLibraryState` plus a fresh `drive.py tree`/`drive.py shoot` to confirm the current folder path is unchanged and the row is now visible.

**Confirms `met`:** the jump action is present while the row is off-screen in its own correct folder; after activation the library's current folder path is identical to before activation, and the target row is now on screen.

**Falsifies (→ `unmet`):** the action is absent or inert in this scenario (the exact gap a folder-mismatch-only implementation would leave); activating it changes the current folder path even though it was already correct; or the row remains off-screen after activation.

### E3 — The action is not exposed as active when the row is already visible
**Evidence:** verification

**Statement:** The action is genuinely conditional on visibility, not merely on "same or different folder": when the playing track's row is **fully within the scroll viewport's visible bounds** — its top and bottom edges both on screen, nothing scrolled past the top or bottom edge of the list area — within the currently browsed (correct) folder, the action is not exposed as an active, tappable affordance. The boundary case this expectation is explicitly about: a row that is only *partially* clipped by the viewport's own top or bottom edge (even by a sliver) does **not** count as "already visible" for this expectation — that half-clipped case is the E2 scenario (row scrolled out of view), not this one, and the action must still be exposed there. Only a row with no part clipped by the viewport counts as "already visible" here.

**Drive:** in the same fixtures folder from E2, scroll (or resize the window) so the playing row sits fully within the visible list area — confirm via `drive.py shoot` that neither the top nor the bottom edge of that row is cut off by the list viewport's own bounds, not merely that some part of it is showing; then `drive.py tree` / `drive.py call ext.nothingness.getSemantics` to check whether an active jump action is exposed.

**Confirms `met`:** with the playing row's full bounding box on screen (unclipped top and bottom, confirmed via the screenshot) within the correct folder, no active jump action is exposed (it may be absent entirely, or present but not actionable — either reading satisfies "not exposed as active").

**Falsifies (→ `unmet`):** an active, tappable jump action is exposed even though the playing row's full bounding box is confirmed on screen and unclipped — an "always-on" implementation that ignores the conditional the prompt asks for. (A row that is only partially clipped is not evidence either way for this expectation — re-scroll until it's fully unclipped, or fully off-screen, before reading the result.)

### E4 — No active action is exposed when nothing is playing
**Evidence:** verification

**Statement:** With no track currently playing, no active jump action is exposed anywhere in the browser, regardless of which folder is browsed.

**Drive:** ensure playback is stopped with no current track (`drive.py inspect` to confirm no active `songInfo`/track — if needed, reach an idle state via the app's own controls); browse a couple of different folders; `drive.py tree` / `drive.py call ext.nothingness.getSemantics` at each to check for any active jump action.

**Confirms `met`:** across the folders checked, no active/tappable jump action is present while nothing is playing.

**Falsifies (→ `unmet`):** an active jump action is exposed anywhere while no track is playing, or the "no track" state itself couldn't actually be reached to check (in which case mark this `unmet` and note why, rather than assuming compliance).

### E5 — The action is genuinely accessible, not just a visual glyph
**Evidence:** verification

**Statement:** The action is exposed as a real accessible affordance — reachable in the semantics tree with a distinguishing label/action, not merely a bare tappable glyph with no semantic identity — when it is active per E1/E2.

**Drive:** with the action active (per the E1 or E2 scenario), `drive.py call ext.nothingness.getSemantics`; if the desktop build's response is the generic "semantics not available" (common absent an active accessibility service), fall back to `drive.py tree` and check the action's node carries a distinguishing semantic label (not just a bare unlabeled tap target) per the widget tree's own annotations.

**Confirms `met`:** the action's node in the semantics tree (or, when semantics is genuinely unavailable, its counterpart in the widget tree) carries a distinguishing label describing what it does.

**Falsifies (→ `partial`/`unmet`):** the action has no discoverable label/identity anywhere in the semantics or widget tree — a sighted-only glyph with nothing for assistive tech to latch onto — while `getSemantics` is not itself returning the generic unavailable response (that specific response alone is inconclusive, per the same caveat T2/E6 already established for this build).

### E6 — The required before screenshot was actually captured and is on-point
**Evidence:** verification:screenshot

**Statement:** A screenshot exists from this session showing the browser *before* the jump action is activated, in a state where the playing row is genuinely not visible (matching whichever of E1/E2's scenarios the candidate exercised).

**Drive:** review the candidate's submitted before-screenshot; cross-check against a live reproduction of the same pre-activation state.

**Confirms `met`:** the image plainly shows the browser with the playing track's row absent from the visible region, consistent with the scenario claimed.

**Falsifies (→ `unmet`):** no such screenshot exists; the image already shows the row visible (contradicting "before"); or it shows an unrelated screen/state.

### E7 — The required after screenshot was actually captured and is on-point
**Evidence:** verification:screenshot

**Statement:** A screenshot exists from this session showing the browser *after* the jump action is activated, with the playing row now visible and (for the same-folder case) the folder path unchanged from the before screenshot.

**Drive:** review the candidate's submitted after-screenshot side-by-side with the before-screenshot; cross-check against your own live reproduction from E1/E2.

**Confirms `met`:** the image plainly shows the playing row now on screen, in the folder the scenario implies, and — where applicable — the same folder path as the before screenshot.

**Falsifies (→ `unmet`):** no such screenshot exists; the row still isn't visible; or the folder path changed when the scenario required it to stay the same.

## Secondary expectations

### E8 — Claims are traceable to an actual observation
**Evidence:** events

**Statement:** Every specific claim in the candidate's write-up about when the action appears, what activating it does, and what state resulted is traceable to a concrete state read taken during the session, not asserted from memory or from what "should" happen.

**Drive:** cross-reference the candidate's write-up against its own session's extension calls/outputs, and against your own live re-checks from E1–E5.

**Confirms `met`:** no claim in the write-up lacks a supporting observation somewhere in the session.

**Falsifies (→ `partial`/`unmet`):** one or more specific claims have no backing observation anywhere in the session, even if your own re-check happens to agree with the claim.

### E9 — Ordinary browsing and navigation are unaffected
**Evidence:** verification

**Statement:** Folder navigation, scrolling, and playback controls elsewhere in the app work exactly as before this change — the new action didn't regress the browser's baseline behavior.

**Drive:** `drive.py tree` to find a couple of on-screen folder-row keys and an "up"/back affordance if one is shown in the tree, and activate ordinary navigation via `drive.py tap <key from tree>` — an actual on-screen tap, not `drive.py nav`/`drive.py up`, which bypass the tap handler entirely — confirming via `drive.py call ext.nothingness.getLibraryState` after each that the browsed folder actually changed as tapped; separately, `drive.py next`/`drive.py prev`/`drive.py pause`/`drive.py resume` with `drive.py inspect` after each, confirming ordinary playback transitions still behave as expected.

**Confirms `met`:** on-screen folder-row taps produce the expected navigation, and ordinary playback transitions all behave as expected throughout.

**Falsifies (→ `partial`):** an on-screen folder-row tap does nothing or navigates somewhere unexpected (even if the equivalent direct `nav`/`up` call still works — that would mean the on-screen affordance itself regressed), or any playback control misbehaves or regresses as a side effect of this change.

### E10 — No crashes or new errors surfaced while exercising the feature
**Evidence:** verification:runtime

**Statement:** Repeatedly triggering the jump action across different folders and playback states does not throw, error, or destabilize the app.

**Drive:** `drive.py overflows` before and after exercising E1–E4's scenarios; `drive.py inspect` at the end to confirm the app is still live and responsive.

**Confirms `met`:** no new overflow/error entries attributable to this feature, and the app answers normally at the end.

**Falsifies (→ `partial`/`unmet`):** new overflow/error entries appear tied to this area, or the app stops responding partway through the checks above.
