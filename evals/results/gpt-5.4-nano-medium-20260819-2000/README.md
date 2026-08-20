# gpt-5.4-nano · medium reasoning · 2026-08-19

**13/21** across 7 scored tasks · campaign **$0.9252** incl. retries · accepted tasks **$0.9252** · 779.5k in / 159.1k out · unassisted · judge: Copilot, gpt-5.4-nano-medium-t2-settings-placement-linux, gpt-5.4-nano-medium-t3-settings-placement-color-scheme-linux, nothingness-eval-judge

This campaign scored 13/21 across seven Linux tasks. The model completed straightforward playback and queue flows, while settings, gesture, and persistence tasks exposed gaps in interaction coverage and evidence.

| Task | Score | Outcome | Assisted | In | Out | Reasoning | Cache | Accepted task cost | $/point |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `t1-playback-smoke-linux` | 3 | pass | no | 68.4k | 6.3k | 3.3k | 620.8k | $0.0352 | $0.0117 |
| `t2-settings-placement-linux` | 1 | partial | no | 204.2k | 12.0k | 8.3k | 1504.8k | $0.0871 | $0.0871 |
| `t3-settings-placement-color-scheme-linux` | 2 | partial | no | 55.6k | 10.2k | 7.2k | 1078.0k | $0.0466 | $0.0233 |
| `t4-swipe-to-seek-linux` | 0 | fail | no | 101.4k | 34.5k | 25.3k | 7628.5k | $0.2171 | – |
| `t5-jump-to-now-playing-linux` | 2 | partial | no | 189.7k | 51.1k | 39.5k | 9990.4k | $0.3027 | $0.1514 |
| `t6-dot-song-info-hardening-linux` | 2 | partial | no | 100.5k | 36.8k | 27.4k | 6331.4k | $0.1939 | $0.0969 |
| `t7-opus-shuffled-playlist-linux` | 3 | pass | no | 59.7k | 8.3k | 5.1k | 958.0k | $0.0427 | $0.0142 |
| **Total** | **13/21** | | no | 779.5k | 159.1k | 116.1k | 28111.9k | **$0.9252** | **$0.0712** |

Campaign cost including retries: **$0.9252**. Accepted task cost: **$0.9252**.

## What happened

**t1-playback-smoke-linux** (3) — The live Linux smoke run exercised play, pause, resume, seek, and next on the ten fixture tracks; runtime confirmed the transitions and no overflows.

**t2-settings-placement-linux** (1) — E1: The candidate launched the Linux app, selected Cassette, opened Settings, and captured a genuine screenshot plus semantics. Both show the screen row directly followed by the Tape · Mono cassette variant row.

E2: The candidate did not drive the screen selector through its cycle or verify direct setting changes against the row, so preserved screen behavior was not established.

E3: The candidate did not activate the cassette variant row or issue cassettevariant checks, so preserved variant behavior was not established.

E4: No non-Cassette screens or their representative controls were exercised.

E5: The captured PNG clearly shows the Settings sheet, Cassette as the active screen, and the adjacent screen/variant rows.

E6: The semantics capture independently corroborates the screenshot: screen=cassette at index 5 and variant=Tape · Mono at index 6 with abutting bounds.

E7: Unrelated row ordering and unrelated control functionality were not compared or exercised.

E8: The final runtime inspection found the app live and responsive with zero overflow reports after the Settings/Cassette exercise; no new Flutter crash was observed.

**t3-settings-placement-color-scheme-linux** (2) — Cassette placement and the exact color scheme label were verified with semantics and a genuine screenshot. Coverage was limited because no full screen cycle, on-screen row activation, or non-Cassette regression sweep was completed.

**t4-swipe-to-seek-linux** (0) — E1: The candidate made one atomic synthetic touch drag and captured a release-time image, not a genuine in-flight gesture. The modified Void screen still renders the normal folder crumb and progress hairline.
E2: I found no judge-controlled real swipe capture. The only candidate drag used the fixture path that returns success without moving the Linux hero, so the center-indicator claim is unverified.
E3: No settled post-swipe verification was performed. The available judge capture is idle with no playing track and cannot show a reverted folder line.
E4: The session has one drag only, so there are no two live target values to compare.
E5: The runtime inspection shows no playing track and no before/after positions. The candidate interaction therefore does not prove that release commits a seek.
E6: seek_during.png was captured after the atomic drag call returned; surrounding events contain no incremental pointer updates.
E7: The candidate produced a named post image, but I could not verify it as a settled folder-path screenshot from a live swipe state.
E8: The structural capture reports currentPath null and songInfo null, so it does not corroborate a normal post-swipe folder line.
E9: The tree still contains previous, play, and next semantics and vertical callbacks. No live taps or vertical swipe were exercised by the judge.
E10: The app remained responsive and reported zero overflow entries. A repeated real X11 swipe burst was not run; the candidate mouse assertion is the known fixture limitation.

**t5-jump-to-now-playing-linux** (2) — The candidate preserved different-folder jump behavior and added scroll-to-track plus an accessible semantics label. The predicate still only checks folder mismatch, so the same-folder off-screen action remained absent; final runtime was responsive with no overflow reports.

**t6-dot-song-info-hardening-linux** (2) — Normal- and maximum-scale long-metadata screenshots showed the text inside Dot without overlap. Restart persistence and short-metadata comparisons were not independently demonstrated; final runtime was live with zero overflow reports.

**t7-opus-shuffled-playlist-linux** (3) — The live run queued the ten supplied Opus fixtures once, enabled shuffle, and advanced exactly one track within the fixture set. Event history and final inspection confirmed the transition and a clean runtime.

## Interventions

None — fully unassisted.

## What surprised us

- The Cassette placement and rename were visually and structurally correct, but the candidate did not exercise the full control cycle or non-Cassette regressions.
- The jump-to-now-playing implementation passed the different-folder case but missed the required same-folder/off-screen visibility predicate.
- Several partial scores reflected incomplete persistence or live-gesture verification rather than app crashes.
