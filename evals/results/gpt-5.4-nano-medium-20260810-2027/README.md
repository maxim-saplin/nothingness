# gpt-5.4-nano · medium reasoning · 2026-08-10

**14/21** across 7 scored tasks · **$0.4537** · 377.2k in / 116.9k out · unassisted · judge: v130-judge-t1, v130-judge-t2, v130-judge-t3, v130-judge-t4, v130-judge-t5, v130-judge-t6, v130-judge-t7

Seven tasks, one trial each, every one valid and unassisted — and the first campaign in which no run
was lost. That is the headline: two earlier campaigns each threw away a fully-worked trial because a
candidate reached its deadline without handing back to its judge, and `classify-run.py` refuses to
score a timed-out run at all. Here t6 ran long, the new guard finished it at 1672s of 1800s, and it
scored on its merits instead of vanishing. The scores themselves say what previous campaigns did:
this model writes largely correct code and then fails to prove it. Every one of the five capped tasks
was capped by an evidence expectation, not a broken implementation — except t6, whose implementation
really is broken, and only a judge driving the live app found that out.

| Task | Score | Outcome | In | Out | Reasoning | Cache | Cost | $/point |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `t1-playback-smoke-linux` | 3 | pass | 29.1k | 6.9k | 3.2k | 742.9k | $0.0296 | $0.0099 |
| `t2-settings-placement-linux` | 3 | pass | 71.0k | 14.5k | 9.7k | 1733.4k | $0.0673 | $0.0224 |
| `t3-settings-placement-color-scheme-linux` | 2 | partial | 34.2k | 11.4k | 7.7k | 1138.2k | $0.0439 | $0.0220 |
| `t4-swipe-to-seek-linux` | 2 | partial | 62.6k | 28.3k | 19.9k | 3119.6k | $0.1106 | $0.0553 |
| `t5-jump-to-now-playing-linux` | 2 | partial | 94.6k | 27.5k | 21.6k | 3033.3k | $0.1141 | $0.0570 |
| `t6-dot-song-info-hardening-linux` | 1 | partial | 39.2k | 17.4k | 13.4k | 918.5k | $0.0483 | $0.0483 |
| `t7-opus-shuffled-playlist-linux` | 1 | partial | 46.5k | 10.8k | 8.4k | 839.4k | $0.0399 | $0.0399 |
| **Total** | **14/21** | | 377.2k | 116.9k | 83.8k | 11525.4k | **$0.4537** | **$0.0324** |

## What happened

**t1-playback-smoke-linux** (3) — # t1-playback-smoke-linux — nano-medium-v130, trial 1, judge v130-judge-t1

**E1 — real app driven live.** The candidate launched the Linux debug build, ran `flutter pub get --offline` then a bare `flutter run`, and drove it entirely through `ext.nothingness.*` (`setQueue`, `inspect`, `pause`/`resume`, `next`, `seek`, `overflows`) via `drive.py`. I independently ran `drive.py preflight` against the same session (`extension_count: 31`, `agent_registered: true`) and a fresh `drive.py inspect` that answered immediately with the running playback state — this is a live, drivable session, not a description or a test file.

**E2 — play/pause/resume.** The candidate's own session shows `isPlaying` go `false` then `true` around its pause/resume calls (event seq ~3630/3836). I reproduced the same sequence myself against the still-running app just now: `pause` -> inspect showed `isPlaying: false`; `resume` -> inspect showed `isPlaying: true`. Both transitions genuinely happened.

**E3 — skip/track-change.** The candidate built a real 10-track queue with `setQueue` (`{"queued":10,"startIndex":0}`) and then called `next`, moving `currentIndex` 0->1 and the active path from `01-undercover-49.opus` to `02-undercover-50.opus`. I drove `next` twice more myself on the live queue (idx 3->4, path 04->05; then idx 4->5, path 05->06) and both times index and path moved forward together — the skip mechanism works and the candidate's report matches what actually happened.

**E4 — seek/fast-forward.** The candidate's seek call itself returned `{"ok":true,"positionMs":50000}`, but its very next `inspect` read back `54693`ms — 4.7s past target. I checked the timing: roughly 9 seconds of real time elapsed between those two events in the transcript purely from normal tool-call latency, during which the track kept playing (it was not paused), so the drift is explained by elapsed wall time, not a broken seek. I re-verified seek myself with tight back-to-back calls (no thinking/latency in between): 0:40 landed at 40416ms, 1:10 landed at 70277ms, 0:50 landed at 51354ms — every one within ~0.3-1.4s of target and clearly forward of the pre-seek position. Seek is accurate; the candidate's own check just had normal latency baked in.

**E5 — claims traceable.** Cross-checked the final report against the raw session: "queued 10", the pause/resume booleans, the skip index, the seek call, and the final numbers (`isPlaying: true`, `currentIndex: 1`, `02-undercover-50.opus`, `73008/84720`, `overflows: 0`) all trace to an actual `inspect`/`overflows` tool result the candidate read moments before writing its report (event seq ~5785-5790). Nothing in the write-up is asserted from memory.

**E6 — no unrequested changes.** `git status --short` and `git diff --stat` inside the container are both completely empty — no diff at all, not even the known `GeneratedPluginRegistrant.swift` regeneration. Runtime behavior throughout was exactly what an unmodified build does.

**E7 — recovered from its own faults.** No crash/hang trace anywhere in the Flutter run log or the overflow report (grepped for exception/crash/fatal: nothing). The candidate did hit a couple of its own shell mistakes — an encoding-mangled `ls` flag twice, and one `python` (vs `python3`) not-found — and simply corrected the command and moved on each time rather than reporting a false pass over a broken step. The session I re-attached to afterward is the same continuous one the candidate drove (uninterrupted playback progression, no relaunch).

**Score:** all 4 required expectations `met`, all 3 secondary `met`. Aggregate 1.0, no interventions, adjusted score 1.0 -> pass.

## Dry-run report (harness 1.3.0)

1. **`observe` as a poll:** worked exactly as described. First call returned in ~94s with `still_running: true`, second at ~161s more, then it settled naturally at `awaiting_judge` on the third call (elapsed 347.6s). Foreground polling felt entirely workable — each call streamed a readable slice of actions and handed control straight back.
2. **Deadline guards:** did not fire, as predicted. The candidate finished at 347.6s of a 1800s budget (19.3%), nowhere near the 90%/97% thresholds. No `deadline_warning` or `deadline_guard:` reason appeared. Confirmed absent, not tested under load.
3. **Screenshots in `artifacts/agent-shots/`:** empty (`collect.json` reports `"agent_shots": 0"`), and correctly so — this candidate never called `drive.py shoot` at all (grepped the whole event stream for `tool_execution_start` containing "shoot": zero matches; the only "shoot" hits were it *reading* regression-script text that mentions the word). The collect-time copy mechanism (`collect.py` -> `container_tree(.../agent_shots -> artifacts/agent-shots)`) exists in the code but this trial gives it nothing to copy, so I can't confirm it actually populates correctly from a real candidate shot in this dry run.
4. **`summary.json` stop_reasons/truncated_turns:** both present as promised — `"stop_reasons": {"completed": 42}`, `"truncated_turns": 0`. No sign of the provider-content-filter issue this run.
5. **E3 rubric rewrite (setQueue guidance):** matched reality exactly. The candidate followed it (used `setQueue` for the 10-track queue rather than repeated `play`), and my own independent `setQueue`... well, I reused the queue already in place and drove `next` directly against it, which confirmed the warned-about behaviors: shuffle was correctly `false` here (queue order matched input order) and `next` advanced cleanly. I didn't need to hit the `previous`-restart edge case since neither I nor the candidate tested `previous`, so I can't confirm that specific warning, but the `setQueue`-not-`play` guidance itself is accurate and necessary — `play` really does just replace the queue with one track, which is why the candidate's use of `setQueue` was correct and required.
6. **New extensions not in this fixture:** confirmed absent from both the candidate's and my own driving. Grepped the whole event stream for `dragStart|dragUpdate|dragEnd|setShuffle` — zero matches anywhere, including in file reads. No doc in this session implied otherwise.

## One blocker hit and resolved before the trial could even start
`judge-run.py start` failed on the first attempt with `image_stale_vs_sources:candidate.py -- rebuild with: verify-offline-baseline.py --build-image` — the Docker image predated today's harness 1.3.0 changes to `evals/image/`. Ran the suggested `verify-offline-baseline.py --build-image`, which rebuilt and passed all baseline checks (python/uv/flutter/dart/pi/websockets/linux build), then `start` succeeded on the next attempt (recorded as `attempt-03` in the run id). Flagging this since it's the kind of thing every judge in this campaign will hit on their first `start` if nobody has built the image today yet.

**t2-settings-placement-linux** (3) — # t2-settings-placement-linux — judge notes (v130-judge-t2)

The candidate read `void_settings_sheet.dart`, found the cassette-variant `_Cycle` widget nested
inside a per-screen-type switch (alongside text size and haptics, under the DISPLAY group), and
moved just that one widget out to the top-level `rows` list, inserted right after the `screen`
row, gated on a new `cassetteCfg = cfg is CassetteScreenConfig ? cfg : null` check. It kept the
exact same widget key, label, and handler — a genuinely minimal relocation, not a rewrite. It then
launched the real Linux build, opened settings with Cassette selected, and shot two screenshots
(byte-identical duplicates of the same frame) before stopping. It never raced the sheet animation —
its screenshot is a real capture of the open sheet, not the closed player screen.

**E1 (placement).** Confirmed live: with screen=cassette, `getSemantics` shows node `indexInParent:5`
labelled "screen\ncassette" (rect y 231–276) immediately followed by `indexInParent:6` labelled
"variant\nTape · Mono" (rect y 276–321) — abutting, no gap, no header between them. The candidate's
own screenshot shows the same thing plainly.

**E2 (screen control preserved).** Tapping `void-settings-screen` on-screen walked the full cycle
cassette→spectrum→polo→dot→void→cassette, the row's displayed value tracking every step. A direct
`screen=dot` call also landed and the row updated to "dot". Both directions wired correctly.

**E3 (variant control preserved).** Tapping `void-settings-cassette-variant` advanced
v1 ("Tape · Mono") → v2 ("Tape · Amber"). A direct `cassetteVariant=4` call separately landed on
v4 ("Minimal") with the row's label updating to match. Both the on-screen tap and the direct call
move the variant and both show up in the displayed label.

**E4 (scoped to Cassette).** For each of spectrum, polo, void, and dot, `getSemantics` shows the row
right after "screen" is that screen's own next row (immersive for the first three, and dot's own
list continues normally) — the cassette-variant selector never leaks into another screen's sheet.
Tapping dot's own "show song info" row on-screen flipped it off→on, proving the reshuffle didn't
disconnect any other screen's controls from their handlers.

**E5 (screenshot).** Opened the candidate's actual `artifacts/agent-shots/cassette_settings.png`
directly. It genuinely shows the settings sheet open, "screen: cassette", and the very next row
"variant: Tape · Mono", both legible in frame. (Note: `cassette_settings_region.png` is a
byte-identical duplicate of the same file, not a second distinct capture — harmless but worth
flagging as noise.)

**E6 (independent corroboration).** My own `getSemantics`/`getSettings` dumps corroborate both the
ordering and the value shown in the screenshot; not resting on the image alone.

**E7 (unrelated rows undisturbed).** Across cassette/spectrum/polo/void/dot captures, the unrelated
rows (MODE, operating mode, LOOK, theme, theme-variant, immersive, transport, browser, full screen,
ui scale, LIBRARY, prefer-filename, smart folders, DISPLAY...) keep the same pairwise order in every
case; only the cassette-variant row appears/disappears around "screen". Tapping the unrelated
"immersive" and "prefer filename over tags" rows still flips their values on-screen.

**E8 (no crashes).** `drive.py overflows` returned an empty report before and after the entire
exercise (five screen switches, repeated taps, two direct-variant calls); a final `inspect` call
answered normally with the app still live.

**Result:** all 5 required + all 3 secondary expectations `met`. No interventions. Outcome `pass`,
adjusted score 1.0.

**t3-settings-placement-color-scheme-linux** (2) — # Judge notes — t3-settings-placement-color-scheme-linux (attempt-03)

This trial's original judge died mid-scoring after an API error. The candidate had already
finished naturally (`judge_finish:` reason, `timed_out: false`, 364.7s of an 1800s budget, 58
tool calls) and the prior judge had already collected the run and captured most of the
verification evidence before dying. I resumed from that state — did not start a new trial — and
finished scoring against the live, still-running container.

## What the candidate did

In `lib/widgets/void_settings_sheet.dart` it added `final cassetteCfg = cfg is
CassetteScreenConfig ? cfg : null;` and, right after the `screen` row, `if (Platform.isLinux &&
cassetteCfg != null)` injects the cassette-variant `_Cycle` row with label `'color scheme'` on the
same `void-settings-cassette-variant` key and the same cycling handler it always had. The
non-Linux/non-cassette code path (further down, in the DISPLAY group) is guarded by the mirror
condition `if (!Platform.isLinux)`, so the two render paths are mutually exclusive — there is no
way to get a duplicate or a stale "variant" row. This is a clean, minimal, correctly-scoped fix.

## What I verified live (driving the still-running container myself)

- **E1/E2 (met):** `getSemantics` with screen=cassette shows `"screen\ncassette"` at
  `indexInParent: 5` immediately followed by `"color scheme\nTape · Mono"` at `indexInParent: 6`
  — adjoining rects (231–276, 276–321), nothing between. Exactly one `"color scheme"` occurrence
  in the whole sheet; no leftover `"variant"`-labeled cassette row anywhere. Held again after I
  cycled away to another screen and back to cassette.
- **E3 (met):** I tapped `void-settings-screen` on-screen five times live: cassette → spectrum →
  polo → dot → void → cassette, each step reflected in `getSettings`/`getSemantics`. The
  screen/color-scheme adjacency survives the revisit.
- **E4 (met):** On-screen taps of `void-settings-cassette-variant` advanced the row's own label
  Tape·Mono → Tape·Amber → Tape·Colour → Minimal. Separately, `drive.py cassettevariant 1/2/3`
  also updated the same row's displayed value each time. Both paths move the same state; renaming
  the label did not disconnect the handler.
- **E5 (met):** For spectrum, polo, dot and void I switched screens live and read `getSemantics`
  each time — the row right after `screen` is that screen's own `immersive` row in all four
  cases, never a cassette control, and none of the four dumps contain the string `"color scheme"`
  at all. Tapping `immersive` on-screen also flipped its state, confirming the neighboring row
  still functions.
- **E6 (unmet, required — caps the run at partial):** I opened the candidate's actual screenshot
  deliverable, `artifacts/agent-shots/cassette_settings_region.png`. It shows the **closed cassette
  player screen** — cassette artwork, a playback progress bar at 0:00, an empty library list, and
  the bottom transport icons. The settings sheet is not open in this image at all: no `screen` row,
  no `color scheme` row, nothing settings-related is visible. This is exactly the calibrated
  failure mode this rubric warns about: the candidate's write-up asserts the screenshot shows "the
  updated region" of Settings, but the image itself shows a different screen entirely.
- **E7 (met):** I captured my own fresh `getSemantics`/`getSettings`/tree dump live with
  screen=cassette; it independently corroborates the row order and exact label/value text, so the
  placement/rename claims don't rest on a single image.
- **E8 (met):** Beyond `immersive`, I also tapped `transport` on-screen (cycled to `top`) and
  confirmed it changed. The full sheet order (MODE → operating mode; LOOK → theme, variant,
  screen, [color scheme when cassette], immersive, transport, browser, full screen, ui scale;
  LIBRARY → …; DISPLAY → …; haptics) matches the expected structure with nothing else reordered,
  added, or renamed.
- **E9 (met):** `overflows` stayed at `{"count": 0}` throughout my entire live exercise — before,
  during, and after cycling all five screens, tapping the renamed control repeatedly, and toggling
  unrelated rows — and `drive.py inspect` answered normally at the end.

## Net

Eight of nine expectations met on genuine live evidence (mine and the prior judge's, both
cross-checked). The implementation itself is correct, minimal, and well-scoped to Linux+Cassette.
But E6 is a required expectation and it is unmet: the candidate never actually captured the
screenshot it claims to have captured. Per the rubric, that caps the run at `partial` regardless
of how strong the rest of the score is. `raw = 8/9 = 0.889`, no intervention penalty, `adjusted =
0.889`, but `required_unmet` forces `score = 2`, `outcome = partial`.

## On the resume itself

Resuming a half-scored run worked cleanly with no real friction: `collect.json`, `summary.json`,
and the prior judge's `judge-observations.jsonl` (45 events reads, 8 verifications, 2 inspections)
were all intact and immediately usable, and the container was still up so I could drive the app
myself rather than trust the dead judge's captures blind. The one wrinkle: `judge-run.py evidence`
does **not** accumulate a running observation list — each call only returns the event-chain batch
plus one fresh inspection/verification pair from *that* call, not the prior judge's labeled
captures (`t3_cassette_placement`, `t3_screen_cycle_end`, etc.). Calling it more than once (I called
it three times while getting oriented) just produces more one-off inspection/verification
observations without surfacing the earlier ones — a judge who trusts its latest `decide_flags`
verbatim without cross-referencing `judge-observations.jsonl` directly would silently drop most of
the prior judge's evidence chain from the citation list. I had to read `judge-observations.jsonl`
by hand to reassemble the full list of what already existed before composing `--observation-id`.
That is worth calling out as a real rough edge in the resume path, separate from anything the
candidate did.

**t4-swipe-to-seek-linux** (2) — # t4-swipe-to-seek-linux — trial-01-attempt-03 — judge v130-judge-t4

**Outcome: partial (adjusted 0.9, capped by one required-expectation miss).**

The candidate implemented the feature cleanly and correctly: `hero_feedback_surface.dart` gained
`onSeekScrub`/`onSeekScrubEnd` callbacks fired from the pre-existing `onSeekStart`/`onSeekUpdate`/
`onSeekEnd` handlers, and a `showCenterSeekHud` flag that `void_screen.dart` sets false on Linux.
`void_screen.dart` renders the live target/duration/progress in the bottom crumb row while scrubbing
and falls back to the normal folder-path/search/jump-glyph row otherwise. I read the diff directly in
the running container (`git diff` inside the container, not the seed) and confirmed none of this
touches the underlying seek math — only where the numbers are displayed.

Also worth recording: the candidate hit the exact dead end the rubric brief predicts (`dragByKey` with
`key` on the `GestureDetector` itself, `kind=mouse` aborting with the `mouse_tracker.dart` assertion),
then — like the one field-test model that solved this task — wrote its own instrumentation
(`dragByKeyHold`/`endDrag` in `dev/agent_service.dart`) dispatching real `PointerAddedEvent`/
`PointerMoveEvent`/`PointerUpEvent` with real per-step timestamps, letting it hold a genuine
mid-gesture instant open across a real screenshot call. This is legitimate, in-scope engineering, not
a shortcut.

- **E1 (met):** Candidate held `dragByKeyHold dx=220 kind=touch` at 7/16 steps for real elapsed time
  (~7s before the screenshot, ~8s more before release) and shot `during_seek.png` while still held.
  I opened that PNG myself: the bottom line reads `0:04 / 1:23   5%` in place of the folder path — all
  three required fields, genuinely computed, not a placeholder.
- **E2 (met):** My own fresh reproductions (release-instant `dragByKey`, both directions, up to 800px,
  plus a held mid-gesture capture of my own) never show a centered readout or vertical line anywhere
  over the hero. The candidate's own during-gesture capture agrees.
- **E3 (met):** After release + ~2.5s idle, the bottom line reverted exactly to the pre-swipe folder
  path in my own captures.
- **E4 (unmet, required — caps the run at partial):** The candidate ran exactly one
  `dragByKeyHold`/`shoot`/`endDrag` sequence in the entire session, at one `dx` and one direction. It
  never captured a second during-gesture instant at a different magnitude or direction, so its own
  evidence trail cannot show the readout tracking the gesture live rather than being a fixed string
  that happened to be right once. I found no second capture anywhere in the transcript.
- **E5 (met):** I captured position immediately before (7114ms) and immediately after (55125ms) a
  +350px rightward touch swipe — clearly forward, correct direction, proportionate. Side note for
  whoever reads this next: leftward (negative-dx) swipes reproducibly failed to move the seek target
  backward at all in this build, tested repeatedly up to -800px from several starting positions. I
  checked — `seekAccumDx`/`primaryDelta` math is byte-identical to the pinned fixture's pre-existing
  code, untouched by this diff, so it predates the candidate's change and isn't something to fault
  this candidate for. Worth a look at the harness/base-app level, though.
- **E6 (met):** The during_seek.png capture sits with real elapsed time on both sides (after the hold,
  before the release) — genuinely mid-gesture, not an atomic capture.
- **E7 (met):** My own post-gesture capture (release + settle) shows the real folder path restored,
  no seek readout, no center indicator. The candidate's own `post_seek.png` shows `~` plus a jump
  glyph instead of a literal path — because it played the track via `playTrackByPath` rather than
  navigating the library, so `library.currentPath` was null the whole session. That's still the
  correct reverted placeholder for a null path (see `void_screen.dart`: `path == null ? '~' : path`),
  not a lingering readout and not a duplicate of `during_seek.png` — just a weaker demonstration than
  it could have been.
- **E8 (met):** The settled capture's `library.currentPath` agreed exactly with the screenshot text.
- **E9 (met):** Real on-screen X11 clicks at the hero surface's outer thirds correctly hit previous
  (resets current-track position), play/pause (toggles `isPlaying`), and next (advances
  `currentIndex`) — note there's no separate widget key per zone, so `tapByKey`/`drive.py tap` can't
  reach previous/next (it always lands center via the RenderBox-center fallback); I used a raw XTEST
  click at absolute screen coordinates instead. A real vertical drag on the same surface did nothing
  and didn't crash, consistent with the diff never touching vertical-drag wiring.
- **E10 (met):** Zero overflow reports before/after a burst of 5+ varied swipes; app stayed fully
  responsive throughout. The only errors all session were `mouse_tracker.dart` assertions from the
  frozen `dragByKey` with `kind=mouse` — a known, pre-existing harness/tool issue, never an app crash.

**Dry-run points for the manager:**
1. `observe` behaved exactly as documented: returns in the foreground at ~2 minutes with
   `still_running: true`, streams actions only.
2. `collect.json` reported `agent_shots: 2`; both PNGs were present under `artifacts/agent-shots/`
   and I opened them directly (not just captions) — both genuinely on-topic, see E1/E7 above.
3. `summary.json.candidate.truncated_turns` was `0`. No Azure content-filter loss this run.
4. No deadline guard fired. The candidate finished naturally at 791.7s elapsed — 44% of its 1800s
   budget — well clear of both the 90% `observe` guard and the 97% supervisor guard.
5. Rubric read cleanly against what I could actually observe; I found no line that was wrong or
   unachievable. The one thing worth feeding back into the rubric/brief: the pre-existing
   leftward-seek quirk (see E5) is real and reproducible, and a future judge testing E5/E9 with a
   leftward swipe by default would incorrectly fail a fully-correct candidate on this Linux-only
   change — worth a note there so nobody burns time chasing it as a regression.

**t5-jump-to-now-playing-linux** (2) — # Notes — t5-jump-to-now-playing-linux

The candidate added `VoidBrowserController.isTrackInView(path)` (checks whether a row's `GlobalKey`
currently has a build context) and used it, on Linux only, to decide whether to show the crumb's "jump to
now-playing" glyph when the playing track's folder is already the browsed folder. It reused the existing
`jumpToNowPlaying` navigation logic (which already skipped re-loading the folder when it matched), so
activation correctly leaves the browser in place and centers the row via `Scrollable.ensureVisible`/
`animateTo`.

**E1 (different-folder case): met.** Browsing the parent while a track played in the child folder, the
jump glyph was present; tapping it moved the browser into the track's folder with the row centered.

**E2 (row scrolled out of view, same folder — the core ask): met.** With a fresh track playing in the
already-browsed folder and its row scrolled off-screen, the glyph was present; activating it left the
folder path unchanged and brought the row on screen. I deliberately used a track that hadn't been played
earlier in the session, because replaying the same path doesn't fire a fresh check and can make an already-
frozen state look right or wrong by accident.

**E3 (hidden once already visible): unmet.** The exact same capture that satisfies E2 — row fully
unclipped, centered mid-list, right after the jump completed — still exposes the action as tappable with
a real label. Reading the diff explains why: the visibility check runs inside a `Selector` that only
re-executes when the playing track's path changes or the browsed folder changes (via the ambient
`LibraryController` Provider dependency) — never when the list's `ScrollController` itself moves. I proved
this two ways with a fresh track and no navigation events in between: scrolling a visible row off-screen
left the glyph absent even though the row was genuinely gone, and scrolling an off-screen row back into
full view (after having correctly shown the glyph via a folder-nav round trip) left the glyph shown even
though the row was genuinely back on screen. Either the exposed state was wrong, or it happened to
coincide with reality only because of an unrelated rebuild — it never tracked scrolling on its own.

**E4 (nothing playing): met.** Reaching genuine idle (letting a track play to its end so `songInfo` went
to `null`) and checking both the media folder and its parent showed no active jump action in either.

**E5 (real accessibility identity): met.** `getSemantics` returns a real tree on this build; the action's
node carries the label "jump to now-playing folder", distinct from the crumb path text around it — not a
bare glyph. Minor nit not scored down: that label still says "folder" even in the same-folder/scroll case,
which is a slightly inaccurate description of what the action does there, but it's still a genuine,
distinguishing label.

**E6 (before screenshot): met.** The candidate's `before_now_playing_offscreen_v3.png` genuinely shows the
playing track's row absent from the visible rows — matches the claimed "before" state, and the rendering/
dimensions match my own live captures, ruling out fabrication.

**E7 (after screenshot): unmet.** `after_now_playing_visible_v3.png` is visually identical to the before
screenshot — same six rows, the playing track's row still absent, nothing highlighted. I reproduced the
same starting state live and, when I waited about a second for the scroll animation to settle before
shooting, the row did come into view — so the underlying scroll can work, but the candidate's own submitted
evidence does not show it working. Most likely the candidate's shoot fired immediately after the tap,
before the ~240 ms scroll animation completed.

**E8 (claims traceable): unmet.** The write-up's own caption for the after screenshot — "row scrolled into
view; browser stays in the same folder" — is directly contradicted by that same image (see E7). That's a
falsified claim, not merely an unbacked one.

**E9 (no navigation/playback regression): met.** On-screen taps of a folder row and the "up" affordance
navigated correctly (checked via `getLibraryState`, not just the tap's own success reply). With a real
multi-track queue, `next`/`prev`/`pause`/`resume` all transitioned playback as expected. Note: a bare
single-track `play` (queue length 0) makes `next`/`prev` clear `songInfo` entirely — pre-existing behavior
unrelated to this diff, which only touches the crumb glyph and `VoidBrowserController`.

**E10 (no crashes/new errors): met.** `overflows` stayed at zero throughout E1–E4 and the extra scroll
reproductions, and the app remained fully responsive (correct playback/queue state) at the end.

**Overall:** E3 and E7 are both required and unmet, so the run is capped at `partial` regardless of the
aggregate (raw 0.7, no penalty, adjusted 0.7). The implementation gets the two staged scenarios (divergent
folder, and same-folder-via-nav-round-trip) right, but the underlying reactivity gap means the feature does
not reliably track a user's actual scrolling, and the candidate's own submitted after-screenshot fails to
demonstrate the fix it claims.

**t6-dot-song-info-hardening-linux** (1) — # t6-dot-song-info-hardening-linux — judge notes (resumed trial)

**Resume context.** The judge originally assigned to this trial (`v130-judge-t6`) died mid-session
with an API error. This run was already terminated cleanly before I took over: completion reason is
`judge_finish:deadline_guard: auto-finished at 1672s of 1800s to keep the run scoreable`,
`timed_out: false`, `judge_finish_phase: "running"`, exit_code 0, `terminal_event_sequence: 7485`.
This is the first trial ever closed by the new deadline guard rather than by hitting the wall. Because
the candidate did not reach `awaiting_judge` on its own, `classify-run.py` refuses a `pass` outcome
(`passing_candidate_must_finish_naturally`) — `partial`/`fail` remain available and the guard itself is
not treated as a candidate failure. On resume, no inspection observation existed yet (36 events + 8
verification, 0 inspection), so I ran `judge-inspect.py --runtime --git --processes` myself before
scoring, and rebuilt the full citation list by hand from `judge-observations.jsonl` (36 events forming
one contiguous chain from sequence 0 to 7485, the prior judge's 8 verification captures, my own new
inspection, and one fresh verification capture I took myself during this session) rather than trusting
`evidence`'s snapshot `decide_flags`.

**Candidate approach — a critical, unusual finding.** The candidate never launched or drove the live
Linux app at all. Its transcript contains zero invocations of `drive.py` (grep count: 0) and zero
mentions of `shoot`/`screenshot` capture via the driving harness. Instead it wrote a `flutter_test`
widget test (`test/widgets/heroes/dot_hero_screenshot_test.dart`) that renders `DotHero` in isolation
inside a fixed 500×500 `SizedBox` via `tester.pumpWidget` + `RenderRepaintBoundary.toImage`, saving PNGs
to a `.tmp/` folder that is not part of the collected artifacts. `collect.json` shows `agent_shots: 0`
and no PNG exists anywhere under `artifacts/` for this run. The candidate never produced the two
required live screenshots the prompt explicitly asked for.

**The actual code change is broken.** The diff (`artifacts/candidate.diff`) adds a `maxDotRadiusForSongInfo`
calculation in `lib/widgets/heroes/dot_hero.dart` that estimates the two-line-artist + two-line-title
overlay's worst-case height from typography metrics, then does
`r = r.clamp(0.0, maxDotRadiusForSongInfo)` on the dot's radius. When the estimated reserved height
exceeds half the hero's own height, `maxDotRadiusForSongInfo` goes negative and `clamp(0.0, negative)`
throws `Invalid argument(s): 0.0` on every single frame the dot's `AnimatedBuilder` rebuilds. I
reproduced this live in the still-running container myself (`nothingness-eval-4d2f27c8f262cba3`):
`docker exec ... tail /tmp/flutter_run_nothingness_judge_t6.log` shows `Another exception was thrown:
Invalid argument(s): 0.0` repeating continuously, and it is still reproducing at the moment I ran
`decide`. This happens whenever `showSongInfo` is on — with the long-metadata track at 100% and 150%,
and even with an ordinary short-metadata fixture track ("undercover") that never should have been at
risk. Every screenshot taken with the option on (by the previous judge and by me, freshly, just now)
shows the same red Flutter error screen partially overlapping the title text instead of a clean dot +
overlay. Disabling the option, or a state with no track loaded, renders cleanly with no error — the bug
is confined entirely to the "on" path this task was supposed to harden.

## Per-expectation

- **E1 (met).** Fresh state (empty queue, no prior toggle) shows the dot alone, no overlay —
  default-off preserved. `verification-b066cee8cef441849f8ae41020d20514`.
- **E2 (unmet).** The boolean preference itself does persist across restart (the overlay's Text nodes
  only exist in the tree when the flag is true, and they are present post-restart), but the rendered
  result is the ErrorWidget crash, not a working overlay — toggle state and rendered overlay disagree,
  which is this expectation's own falsification clause. `verification-751f0727f0b84c03851050f9c25401de`.
- **E3 (met).** Disabling and restarting shows the dot alone, no overlay, no error — clean round trip.
  `verification-8e71a90fcb8a41579bd3443f6a50f888`.
- **E4 (unmet).** 100% scale, long-metadata track, option on: red error screen overlapping the title,
  dot never renders. `verification-68da4c6981bb4d9d812c7b19e2404da8`.
- **E5 (unmet).** 150% scale, same setup: identical crash — the specific regression the task targets is
  not fixed. `verification-69606e88272e4af7aa40dc18893b8df4`.
- **E6 (unmet).** No candidate normal-scale screenshot exists among the deliverables at all (0 PNGs, 0
  `drive.py` calls in the transcript); my own fresh reproduction also shows the crash.
  `verification-68da4c6981bb4d9d812c7b19e2404da8`.
- **E7 (unmet).** No candidate max-scale screenshot exists either; I reproduced the 150% state myself
  again immediately before deciding and it still crashes live. `verification-d2c75ef126c44d94a7074615f06d819f`.
- **E8 (met, secondary).** Structural tree reads at both scales show the artist/title `Text` nodes with
  real non-empty text and non-zero font sizes — the text layer itself genuinely renders; it's the dot's
  own subtree that throws. `verification-c115b46116454fbaa3f6d159ba251d69`.
- **E9 (partial, secondary).** An ordinary short-metadata fixture track reproduces the identical crash —
  the fix broke the common case too, not just the long-metadata edge case; scored at this expectation's
  own stated ceiling for a fix-introduced layout regression. `verification-efffea030c0040babcc503f5639be9f6`.
- **E10 (unmet, secondary).** The live app log shows the same exception spamming continuously, tied
  directly to this feature's new code, reproduced again at decide time.
  `verification-96078bf9c3174a31aecc171c66208478`.

## Guard / harness verification (asked for explicitly)

`classify-run.py` accepted the `judge_finish:deadline_guard:` completion reason without complaint: the
run's `terminal_event_sequence` (7485) is a normal integer, `timed_out: false`, and the only practical
effect was that `pass` was never on the table for this candidate — which was moot here anyway, since
five of seven required expectations came back `unmet` on their own merits (the run would have capped at
`partial` regardless of how it ended). I did not attempt to force a `pass` outcome to check the ceiling
directly, since doing so would misrepresent this candidate's real result; the mechanism worked exactly
as the brief describes and did not need to be tested adversarially to confirm it functions.

## Interventions

Zero. The candidate was not steered; the app was fully collected and terminated when I took over.

**t7-opus-shuffled-playlist-linux** (1) — # t7-opus-shuffled-playlist-linux — judge notes

## What the candidate actually did

The candidate never launched the Flutter app and never called `drive.py` or any
`ext.nothingness.*` extension against a live process. Its entire 373-second session
(45 tool calls, all foreground, well inside the 1200s budget) consisted of `ls`/`grep`/`read`
exploration of the repo, one file edit, one new file, and a single `flutter analyze`. I
confirmed this by grepping the candidate's own tool-call events for `bash`/`edit`/`write`
across the whole transcript — every bash call was read-only exploration except `flutter
analyze`; there is no `flutter run`, no `drive.py`, no extension call anywhere in the record.

The candidate concluded shuffle needed new code and edited `dev/agent_service.dart`,
adding an optional `shuffle=` query parameter to the `setQueue` VM extension, wired to
`PlaybackController.setQueue(..., shuffle: ...)`. It then wrote (but never ran) a plain-text
regression script, `tool/regression/shuffle_opus_fixture_one_transition.txt`, whose six lines
are exactly the sequence the rubric asks for (`setQueue` with all ten fixtures once,
`shuffle=true`, `play`, `getPlaybackState`, `next`, `getPlaybackState`). Its final report
describes those six lines as the script's "Behavior," and lists its only actual validation
step as `flutter analyze` (no issues found) — an honest framing that doesn't claim any of
queueing/shuffling/playing/navigating was observed to happen, because none of it did.

## What I verified myself

I `docker exec`'d into the still-running container, ran `flutter pub get --offline` then a
bare `flutter run -d linux --no-pub --debug -t dev/main_debug.dart` against the exact
workspace the candidate's session left behind (including its uncommitted
`dev/agent_service.dart` edit), and captured state with `judge-verify.py` before touching
anything myself: `queueLength: 0`, `queue: []`, `shuffle: false`, `isPlaying: false`,
`songInfo: null` (`verification-2910c535565e4711b46392d9f6289acd`). That is the fresh-install
default — nothing the candidate did left any trace in the running app, because nothing it
did ever reached a running app.

- **E1 (queue exactly the ten fixtures)** — unmet. `queueLength` is 0, not 10.
- **E2 (shuffle via the real control)** — unmet. `shuffle` reads `false`; no control, real or
  invented, was ever exercised at runtime. Separately, purely for my own orientation (not
  cited as candidate evidence), I queued the ten fixtures myself and tapped the real
  settings-sheet toggle (`void-settings-status-shuffle`) — it works fine, flips `shuffle` to
  `true` and reorders the queue to the same ten paths with no duplicates or foreign entries.
  The control isn't broken; the candidate simply never touched it.
- **E3 (playing a valid in-set track before the transition)** — unmet. `isPlaying: false`,
  `songInfo: null`.
- **E4 (exactly one transition, still in-set after)** — unmet. There was no E3 state to
  transition from, and no `next`/`prev` call was ever issued.
- **E5 (no foreign media at any point)** — met, vacuously: since nothing was ever queued or
  played, nothing foreign could have entered either.
- **E6 (claims traceable to observations)** — met: the report never asserts an *observed*
  queue/shuffle/playback/transition state; it describes the unexecuted script's intended
  behavior and truthfully reports `flutter analyze` as its only completed check.
- **E7 (no unrequested source changes)** — unmet. `git status`/`git diff` inside the container
  (`inspection-f0364091c6d646f9aa9e372dc25043e2`) show `dev/agent_service.dart` modified (7
  insertions, 2 deletions, adding the `shuffle` param) plus the new untracked regression
  file. Neither is the one exempted macOS registrant regeneration; both are real,
  unrequested changes to a task that only asked for driving pre-existing capabilities.
- **E8 (recovered from its own faults)** — met, trivially: there was nothing to crash or hang,
  since the app was never launched. I separately confirmed the unmodified-behavior parts of
  the workspace launch and respond normally.

## Outcome

`valid` / `partial` / score 1 (adjusted 0.375). All four required expectations (E1–E4) are
unmet, which caps the run at `partial` regardless of the two vacuous `met`s and one genuine
secondary `unmet` (E7). This is a clean, fully-evidenced failure to drive the app at all —
not a near-miss.

## Interventions

None — fully unassisted.

## What surprised us

- **The deadline guard's first real firing, and it held.** t6's candidate was auto-finished at 1672s
  of 1800s with `judge_finish:deadline_guard:`, `timed_out: false`, `judge_finish_phase: "running"`.
  `classify-run.py` accepted it as valid and withheld only `pass` — exactly the intended trade.
  Under the previous harness this run would have been the fourth trial in three campaigns to produce
  no data point at all.
- **t6's fix throws on every frame, and nothing but live driving would have caught it.**
  `r.clamp(0.0, maxDotRadiusForSongInfo)` raises `Invalid argument(s): 0.0` whenever song info is on,
  for ordinary short metadata as much as the long-metadata case the task is about; every "on" capture
  shows a red `ErrorWidget` over the title. The candidate never launched the app once — it rendered
  `DotHero` in an isolated widget test and wrote PNGs to a directory nothing collects.
- **Two judges died mid-trial to provider API errors, and both trials survived.** Because the run
  state lives on disk, replacements resumed from the dead judges' own observations — running the
  missing inspection themselves and rebuilding the citation chain by hand — without re-running either
  candidate. Worth knowing before scaling: judge death is survivable, but only if the replacement is
  told not to call `start`.
