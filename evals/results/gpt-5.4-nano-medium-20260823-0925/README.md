# gpt-5.4-nano · medium reasoning · 2026-08-23

**18/21** across 7 scored tasks · campaign **$0.5556** incl. retries · accepted tasks **$0.5556** · 428.4k in / 105.3k out · unassisted · judge: claude-judge-t5, copilot-cli, copilot-cli-judge, judge-t3-retry0

Seven fresh, isolated Linux evaluations of gpt-5.4-nano/medium produced 18/21 points without interventions: the model consistently shipped working, scoped changes, while three partials were capped by conditional-behavior or evidence requirements.

| Task | Score | Outcome | Assisted | In | Out | Reasoning | Cache | Accepted task cost | $/point |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `t1-playback-smoke-linux` | 3 | pass | no | 22.6k | 6.2k | 3.2k | 561.9k | $0.0247 | $0.0082 |
| `t2-settings-placement-linux` | 3 | pass | no | 44.5k | 12.9k | 8.7k | 1817.1k | $0.0626 | $0.0209 |
| `t3-settings-placement-color-scheme-linux` | 3 | pass | no | 38.7k | 11.0k | 6.4k | 1277.7k | $0.0483 | $0.0161 |
| `t4-swipe-to-seek-linux` | 2 | partial | no | 72.0k | 23.2k | 15.5k | 4377.6k | $0.1321 | $0.0661 |
| `t5-jump-to-now-playing-linux` | 2 | partial | no | 136.1k | 20.7k | 14.1k | 3678.2k | $0.1272 | $0.0636 |
| `t6-dot-song-info-hardening-linux` | 2 | partial | no | 68.9k | 23.9k | 17.6k | 3527.2k | $0.1154 | $0.0577 |
| `t7-opus-shuffled-playlist-linux` | 3 | pass | no | 45.6k | 7.3k | 4.7k | 1294.8k | $0.0453 | $0.0151 |
| **Total** | **18/21** | | no | 428.4k | 105.3k | 70.1k | 16534.5k | **$0.5556** | **$0.0309** |

Campaign cost including retries: **$0.5556**. Accepted task cost: **$0.5556**.

## What happened

**t1-playback-smoke-linux** (3) — # T1 · Playback smoke (Linux) — judge notes

**Run:** `t1-t7-gpt-5.4-nano-medium-t1-playback-smoke-linux-run-ac909e508369`
**Model:** gpt-5.4-nano (thinking: medium) · **Outcome:** pass · **Score:** 3 (raw 1.0, no interventions)

## What the candidate did
It launched the real Linux build (after a few early relaunches where `flutter run` hadn't yet
printed the VM-service URI), attached the `ext.nothingness.*` extension surface, then drove a full
smoke test via `drive.py`: `setQueue` of all 10 fixture tracks at index 0, `play`, `pause`,
`resume`, `next`, and `seek 00:01:00`. It read `getPlaybackState`/`inspect` after each step and
reported the observed flags/positions rather than assuming them.

## What I verified myself (live, same container session)
I confirmed the session is still live — `drive.py contract` returned 31 registered extensions — and
reproduced every transition myself, capturing a `judge-verify.py` bundle at each state:

- **E1 (met):** Live isolate answering; extensions enumerable; full verification bundle captured
  (`verification-4f84c89e`). Not a `flutter test` run, not a code reading.
- **E2 (met):** Runtime lens read isPlaying=true at idx0 (`verification-4f84c89e`), isPlaying=false
  after `pause` (`verification-67499e34`), isPlaying=true after `resume` (`verification-fa6b6bda`).
  The full play→pause→resume transition, observed not assumed.
- **E3 (met):** On a queue at index 0 (01-undercover-49.opus), `next` advanced currentIndex 0→1 and
  the active path to 02-undercover-50.opus, still playing (`verification-3891951800`).
- **E4 (met):** From a pre-seek position of 25760ms on track02, `seek 0:50` landed at 50565ms —
  within +0.6s of the 50000ms target and clearly forward (`verification-f601eb50`). This is the
  exact failure the rubric warns about (a claimed FF that never moved), and here it genuinely moved.
- **E5 (met):** Every specific claim in the final report (queued:10, play true, pause false +
  spectrumNonZero false, resume true, next ok, seek positionMs:60000, final currentIndex:1
  pos 62698) traces to a `getPlaybackState`/`inspect` capture in the session's own event stream.
- **E6 (met):** Inspection git lens shows empty status and empty diff_stat — no source changes at
  all — and my live re-check behaved exactly like an unmodified build.
- **E7 (met):** The early VM-URI launch misses were recovered by relaunching until the isolate
  registered; `drive.py overflows` returned 0 reports and the run log had no crash/exception traces.
  The same session answers live now.

## Verdict
Clean, honest smoke test. All four required expectations met and all three secondary met → pass, 3.

**t2-settings-placement-linux** (3) — # t2-settings-placement-linux — judge notes

**Run:** t1-t7-gpt-5.4-nano-medium-t2-settings-placement-linux-run-8a43a340073a
**Model:** azure-openai-responses / gpt-5.4-nano / medium (identity verified)
**Outcome:** pass (score 3, raw 1.0, no interventions)

## What the candidate did
It edited `lib/widgets/void_settings_sheet.dart` only: inserted `if (cfg is CassetteScreenConfig) ...displayRows(cfg)` immediately after the `_Cycle('void-settings-screen', ...)` row, and guarded the original DISPLAY-section copy with `if (cfg is! CassetteScreenConfig) ...displayRows(cfg)` so the cassette rows are not duplicated. It added a widget test, ran `flutter analyze` (clean) and the sheet test (green), launched the Linux build, and captured screenshots. The diff is scoped to the cassette branch and the row position; no handlers or ids were changed.

## What I verified live (driving the running Linux build myself)
- **E1 (met, required):** With Cassette selected, `getSemantics` shows the `screen / cassette` row (indexInParent 5, rect y 231–276) immediately followed by the cassette `variant / Tape · Mono` row (indexInParent 6, rect y 276–321). Abutting y-ranges, no group header or gap. The captured screenshot shows the same: "screen cassette" directly above "variant Tape · Mono".
- **E2 (met, required):** Tapping the on-screen `screen` row five times cycled spectrum → polo → dot → void → cassette, all the way back to the start. Direct `drive.py screen <name>` calls were each reflected in the row's displayed value. Both directions wired.
- **E3 (met, required):** On-screen taps of the variant row advanced Minimal → Tape · Mono → Tape · Amber; direct `cassettevariant <n>` calls also moved the variant and the row's displayed label tracked each one.
- **E4 (met, required):** For spectrum/polo/dot/void the row directly after `screen` is the general `immersive` toggle — never a cassette control. Spectrum's own `bar style` cycled segmented → solid → glow and dot's `show song info` toggled off → on → off when tapped on-screen, so non-cassette screens' own controls still work.
- **E5 (met, required):** A genuine session screenshot (x11 capture bundled by judge-verify) shows the Settings sheet with Cassette active and both the `screen` and `variant` rows in frame and legible.
- **E6 (met):** The semantics dump plus `getSettings` (screenType=cassette) corroborate the screenshot's row order and active screen.
- **E7 (met):** Unrelated rows kept their prior relative order (MODE, operating mode, LOOK, theme, theme-variant, screen, immersive, transport, browser, full screen, ui scale, LIBRARY…); `transport` cycled bottom → top and `smart folders` toggled and restored when tapped.
- **E8 (met):** `overflows` reported 0 before and after repeatedly opening/closing settings and switching screens; the app stayed live and responsive (final `inspect`: alive, overflows 0).

## Notes
Only the settings sheet + its test were touched; no crashes or new errors surfaced. All four prompt clauses (placement, screen control preserved, variant control preserved, screenshot) hold, and the change is correctly scoped to the Cassette case.

**t3-settings-placement-color-scheme-linux** (3) — # Judge notes — T3 · Cassette settings placement + color-scheme rename (Linux)

**Run:** `t1-t7-gpt-5.4-nano-medium-t3-settings-placement-color-scheme-linux-run-885b75439fc8`
**Model:** azure-openai-responses / gpt-5.4-nano / medium
**Outcome:** pass (score 3, raw 1.0, no interventions)

## What the candidate did
It made a single, surgical change to `lib/widgets/void_settings_sheet.dart` (4 insertions, 2 deletions):
1. Renamed the cassette variant `_Cycle` row's label from `'variant'` to `'color scheme'` — the widget key
   `void-settings-cassette-variant` and its cycle handler are untouched.
2. Added `final inlineCassette = Platform.isLinux && cfg is CassetteScreenConfig;` and inserted
   `if (inlineCassette) ...displayRows(cfg)` immediately after the `screen` row, while guarding the original
   bottom placement with `if (!inlineCassette) ...displayRows(cfg)`. So on Linux with Cassette selected, the
   cassette controls render right under `screen`; everywhere else the layout is unchanged.
It built and launched the Linux app, set screen=cassette, opened settings, and captured screenshots. `flutter analyze` was clean.

## What I verified myself (live, driving the running Linux build)
- **E1 (met):** With Cassette selected, `getSemantics` shows `screen`/cassette at indexInParent 5 (rect y231–276)
  immediately followed by `color scheme`/Tape·Mono at indexInParent 6 (rect y276–321) — abutting rects, nothing between.
- **E2 (met):** The row label reads exactly `color scheme`, lowercase like every other label. Exactly one such row;
  no leftover cassette `variant` row (the `variant`/system row above is the unrelated theme variant control).
- **E3 (met):** Tapping the `screen` row on-screen cycles cassette→spectrum→polo→dot→void→cassette (full cycle back
  to start), the row value tracking each step; direct `screen <name>` calls also land and match `getSettings`.
- **E4 (met):** Tapping the `color scheme` row cycles Minimal→Tape·Mono→Tape·Amber→Tape·Colour→Minimal; direct
  `cassettevariant 1/2/3` calls move the variant and the row's displayed value tracks (captured at Tape·Amber). Both
  activation paths work — the rename did not disconnect the handler.
- **E5 (met):** For spectrum/polo/dot/void the semantics contain zero `color scheme` labels and the row after `screen`
  is that screen's own generic control, never a cassette one. Their own controls still work (spectrum bar-count 8→12,
  dot show-song-info off→on).
- **E6 (met):** Genuine screenshot (verification bundle) of the settings sheet with Cassette selected legibly shows
  `screen: cassette` directly above `color scheme: Tape · Mono`.
- **E7 (met):** Semantics + widget tree + `getSettings` dumps taken while Cassette selected corroborate the order,
  exact label, and variant value — the claim doesn't rest on the image alone.
- **E8 (met):** All other rows keep their prior relative order; unrelated controls still respond (transport bottom→top,
  immersive off→on).
- **E9 (met):** Overflows count 0 before and after opening/closing settings, switching all screens, and cycling the
  color scheme control repeatedly; `inspect` answered normally throughout — no crashes or new errors.

## Bottom line
A correct, minimal, Linux-scoped implementation. Every required and secondary expectation is met on live evidence.

**t4-swipe-to-seek-linux** (2) — # T4 — Swipe-to-seek feedback placement (Linux) — judge notes

**Run:** t1-t7-gpt-5.4-nano-medium-t4-swipe-to-seek-linux-run-b51243550ec4
**Model:** azure-openai-responses / gpt-5.4-nano / thinking=medium (identity verified)
**Outcome:** partial (score 2, raw 0.7, adjusted 0.7) — 0 interventions, unassisted.

## What the candidate actually did

It made a clean, correct implementation touching two files. In `hero_feedback_surface.dart` it
gated the existing center seek HUD behind `seeking.value && !isLinux` (so it never renders on Linux)
and added `onSeekFeedback`/`onSeekFeedbackEnd` callbacks fired from the horizontal-drag
start/update/end with the live target, duration and fraction. In `void_screen.dart` it wired those,
on Linux only, into the bottom crumb (folder-path) line so that while scrubbing the line shows
`m:ss / m:ss NN%`, and it added a 600 ms timer that clears the preview after the gesture. It also
added a `ValueKey('hero-feedback-surface')` on the surface — an ancestor of the GestureDetector —
which (unusually for this fixture) makes `dragByKey` actually drive the hero. `flutter analyze`
passes.

The feature genuinely works. I confirmed it live by driving a real held X11 (XTEST) gesture and
reading the app mid-hold: the bottom line showed `3:16 / 7:00 47%` (and `2:49 / 7:00 40%` on another
hold), the hero center showed only "empty" with no HUD or vertical line, and on release playback
jumped to the shown target.

**The gap is proof, not function.** The task required during- and post-gesture screenshots, and the
candidate captured its "during" shot the only way the frozen `dragByKey` allows: one atomic
`dragByKey` call, then a *separate* `drive.py shoot during_seek`. By the time that second command
ran, the 600 ms clear timer had already fired, so `during_seek.png` shows the bottom line back at the
folder path `~ ⊙` — not the seek readout. Its `post_seek.png` is the same folder-path state. So the
candidate never captured the mid-gesture instant its deliverable claims to show.

## Per-expectation

- **E1 (unmet, required):** Candidate's during capture shows the folder path, not target/duration/
  progress, and was a single atomic gesture with no incremental updates over real elapsed time. The
  feature works (I saw it live), but the candidate's own trail never captured it.
- **E2 (met):** No center readout or full-height vertical line at any point — at rest, mid-hold, or
  post-release. Center is gated off on Linux in code and absent in every capture.
- **E3 (met):** After release + ≥1 s settle the bottom line reverts to the folder path with no
  residual readout (post-settle tree + screenshot agree).
- **E4 (unmet, required):** Only one during-gesture capture exists and it carries no legible target
  value, so live value-tracking across differing swipes is not demonstrated in the candidate's trail.
- **E5 (met):** Release commits a real seek. At-rest position 102 229 ms → post-release 243 085 ms
  (~141 s forward jump, far beyond playback drift, in the swipe direction). Reproduced independently
  (121 536 → 219 741 ms on a +220 drag).
- **E6 (unmet, required):** The during-gesture screenshot deliverable traces to a capture taken after
  a single atomic drag settled; its content shows the folder path, so the artifact disproves the
  claim it was submitted to support — the exact recorded field-test failure this expectation guards.
- **E7 (met):** A genuine settled post-gesture screenshot shows the bottom line back to the normal
  folder path, no readout, no center indicator.
- **E8 (met):** A post-settle structural read (tree + runtime) independently corroborates the
  reversion.
- **E9 (met):** On-screen tap zones still work — tapping `transport-play` toggled isPlaying
  True→False; next/prev also fired. The diff leaves tap and vertical-drag wiring untouched.
- **E10 (met):** A burst of varied swipes produced zero overflow/error entries and the app stayed
  live and responsive; run log shows only ALSA/GTK environment noise, no Flutter exceptions.

## Bottom line

Correct, well-scoped implementation of the actual feature, undone on the scored deliverable: the
required during-gesture screenshot shows the cleared folder path rather than the seek readout,
failing the three event-trail expectations (E1/E4/E6) that measure whether the candidate captured its
own gesture. Required-unmet caps the run at **partial**.

**t5-jump-to-now-playing-linux** (2) — # T5 — Jump to now playing (Linux) — judge notes

**Run:** `t1-t7-gpt-5.4-nano-medium-t5-jump-to-now-playing-linux-run-a12a4180da0d`
**Model:** gpt-5.4-nano / medium · **Outcome:** partial (score 2) · raw 0.9, capped by required E3 unmet · no interventions.

## What the candidate did
One-file change in `lib/screens/void_screen.dart`. It reuses the existing `void-crumb-jump-to-playing` ⊙ glyph in the browser breadcrumb and changes its show-condition. Previously the glyph showed only when the playing track lived in a *different* folder (`divergent`). The candidate added a Linux branch: `showJumpGlyph = isLinux ? playingExists : resolveJumpGlyphVisible(divergent)`. It also broadened the semantics label to "jump to now-playing track in browser". `jumpToNowPlaying` loads the parent folder only if `currentPath != parent`, then calls `browserController.scrollToTrack(playingPath)`. Analyzer clean; it hot-reloaded and captured before/after screenshots.

## Per-expectation (verified live by me)
- **E1 (met):** Playing 07-undercover-44 while browsing the *different* parent `/opt/nothingness`, the glyph was present; tapping it navigated into `/opt/nothingness/media` and left the row on screen (idx10, y4–45 in viewport 0–332).
- **E2 (met):** In `/opt/nothingness/media` with track 44's row scrolled off the top (reverse ListView, scrollPosition 0), the glyph was present; tapping scrolled the list to scrollPosition 127, bringing row 44 fully into view, and `currentPath` stayed `/opt/nothingness/media` — it scrolled rather than re-navigated. This is the core hardening ask and it works.
- **E3 (UNMET, required — the cap):** The action is gated only on playback, not visibility. On Linux the code is literally `showJumpGlyph = playingExists`. With track 44's row fully visible and unclipped (y4–45 inside the 0–332 viewport, confirmed in semantics and screenshot), the jump action was *still* exposed as an active tappable button (SemanticsNode#9: actions tap/longPress, isButton, jump label). That is exactly the "always-on" implementation the rubric falsifies.
- **E4 (met):** Idle (isPlaying false, songInfo null): no jump action in tree or semantics at `/opt/nothingness/media`, re-checked at `/opt/nothingness` — same.
- **E5 (met):** getSemantics returned a real tree; the action node carries the distinguishing label "jump to now-playing track in browser" plus the ⊙ glyph and a tap action — genuinely accessible, not a bare glyph.
- **E6 (met):** Candidate's `before_track_54.png` shows the browser with the playing row (54) absent from the visible list and the ⊙ crumb glyph; my own before reproduction (44 off-screen) matches.
- **E7 (met):** Candidate's `after_track_54_delayed.png` shows row 54 now visible+highlighted with the path unchanged; my after reproduction matches (44 scrolled to top, same folder).
- **E8 (met):** Write-up claims are all backed by the candidate's own session reads (6× getLibraryState, 6× getSemantics, 18× tree, 68× shoot, plus the before/after PNGs).
- **E9 (met):** On-screen `void-folder:` tap entered media; `void-up` returned to parent. Playback: with a real folder queue (row-tap builds a 10-track queue) next 46→47 and prev 47→46; pause/resume clean. (next/prev stopping under a single-track `play` is the pre-existing empty-queue quirk, not a regression.)
- **E10 (met):** Overflow count 0 throughout; only ALSA sound-card warnings (no audio device in container), no Flutter exceptions; app live and responsive at the end.

## Bottom line
The candidate correctly shipped the hard same-folder-scroll case (E2) and preserved the cross-folder case (E1), with an accessible label and genuine screenshots. But it implemented the Linux branch as an unconditional "show whenever something is playing", so the action stays active even when the row is already fully visible — failing the required conditional-on-visibility expectation E3. One required unmet caps the run at **partial** despite 9/10 expectations met (raw 0.9).

**t6-dot-song-info-hardening-linux** (2) — # T6 — Dot song-info hardening at max text size (Linux)

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

**t7-opus-shuffled-playlist-linux** (3) — # Judge notes — t7-opus-shuffled-playlist-linux

Run: `t1-t7-gpt-5.4-nano-medium-t7-opus-shuffled-playlist-linux-run-ea25b93c2a6b`
Model: azure-openai-responses / gpt-5.4-nano / medium. Outcome: **pass (3)**. Interventions: 0.

The candidate launched the Linux build, called `setQueue` with the ten mounted fixtures, tapped the
on-screen shuffle toggle, played, and issued one `next`, then reported before=01-undercover-49 /
after=04-undercover-52. I settled every expectation by driving the same live app myself rather than
trusting that write-up.

## E1 — queue is exactly the ten fixtures, each once (met)
My runtime inspect (`verification-03f60...`) shows `queueLength` 10 with the exact ten fixture paths
under `/opt/nothingness/media`, each appearing once — no duplicates, nothing missing, nothing foreign.
All entries `isNotFound:false`.

## E2 — shuffle enabled through the real control (met)
I re-drove the actual on-screen toggle: opened settings and tapped `void-settings-status-shuffle`,
watching `shuffle` flip true→false→true across three inspects. It is genuinely driven by the control,
not a side-channel. `verification-773f9d3d...` captures the restored `shuffle:true`.

## E3 — playing a valid, in-set track before the transition (met)
Runtime inspect showed `isPlaying:true` on `04-undercover-52.opus` (an in-set fixture) with
`isNotFound:false` (`verification-03f60...`). Playback was genuinely advancing on its own (I watched
the current index auto-increment as tracks ended).

## E4 — exactly one transition, result still in-set and valid (met)
I performed one live `next`: index 6 (`09-undercover-46.opus`) → index 7 (`07-undercover-44.opus`).
The index genuinely changed, the post-track is one of the ten fixtures and `isNotFound:false`, and
playback stayed active (`verification-9cd9aa45...`).

## E5 — no foreign media anywhere (met)
Scanning every media path across the session's own setQueue/play/next/inspect events, the only paths
that appear are the ten fixtures. The single non-fixture reference is `media/manifest.json`, which the
candidate read to enumerate the set — it never entered the queue or became current.

## E6 — claims traceable to observations (met)
Each specific claim in the report (queue of 10, `shuffle:true`, before=01-undercover-49,
after=04-undercover-52) maps to a concrete inspect in the session's event stream: the captured inspects
show index 4 = 01-undercover-49 then, after `next`, index 5 = 04-undercover-52.

## E7 — no unrequested source changes (met)
The inspection observation's git `status` and `diff_stat` are both empty — not even the known
`GeneratedPluginRegistrant.swift` regeneration this rubric tolerates. Runtime behavior across E1–E4
matched an unmodified build.

## E8 — recovered from its own faults (met)
`drive.py overflows` returned zero reports and the run log holds no crash/hang traces — only benign
ALSA "no sound card" config noise from the headless container. The same session answered every one of
my live probes and was still playing, so nothing was narrated over a silently-broken app.

## Interventions

None — fully unassisted.

## What surprised us

- The swipe-to-seek implementation worked during a genuine held X11 gesture, but the candidate's separate screenshot arrived after its 600 ms feedback-clear timer and captured the settled path instead.
- The now-playing action correctly navigated and scrolled the browser, yet remained exposed while the playing row was already fully visible because visibility was not part of the Linux gate.
- The dot layout fix held for genuinely long metadata at 100% and 150%; the candidate's own screenshots used short filenames and showed the old overlap, while the live fix over-reserved space enough to collapse the dot.
