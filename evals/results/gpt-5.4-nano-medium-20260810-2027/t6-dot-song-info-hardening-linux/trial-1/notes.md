# t6-dot-song-info-hardening-linux — judge notes (resumed trial)

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
