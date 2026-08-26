# gpt-5-nano · high reasoning · 2026-08-24

**10/21** across 7 scored tasks · campaign **$0.1528** incl. retries · accepted tasks **$0.1528** · 442.6k in / 201.0k out · unassisted · judge: GitHub Copilot CLI, copilot, gpt-5-nano-high-judge, gpt-5-nano-high-t2-settings-placement-linux-retry-0, nothingness-eval-judge

This unassisted seven-task live-app evaluation showed strong performance on the shuffled-playlist task, partial results on settings, swipe feedback, and folder navigation, and failures where the candidate did not launch or left the project unbuildable. Independent judging verified the app behavior rather than relying on the candidate's write-up.

| Task | Score | Outcome | Assisted | In | Out | Reasoning | Cache | Accepted task cost | $/point |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `t1-playback-smoke-linux` | 0 | fail | no | 31.7k | 16.9k | 13.3k | 480.5k | $0.0111 | – |
| `t2-settings-placement-linux` | 2 | partial | no | 42.8k | 33.7k | 28.7k | 957.8k | $0.0208 | $0.0104 |
| `t3-settings-placement-color-scheme-linux` | 2 | partial | no | 127.1k | 34.6k | 28.1k | 2439.4k | $0.0327 | $0.0164 |
| `t4-swipe-to-seek-linux` | 1 | partial | no | 36.5k | 26.1k | 17.2k | 969.2k | $0.0174 | $0.0174 |
| `t5-jump-to-now-playing-linux` | 2 | partial | no | 88.4k | 36.1k | 29.3k | 3349.4k | $0.0360 | $0.0180 |
| `t6-dot-song-info-hardening-linux` | 0 | fail | no | 110.3k | 33.1k | 26.4k | 1363.6k | $0.0259 | – |
| `t7-opus-shuffled-playlist-linux` | 3 | pass | no | 5.9k | 20.6k | 18.8k | 0.0k | $0.0089 | $0.0030 |
| **Total** | **10/21** | | no | 442.6k | 201.0k | 161.7k | 9559.9k | **$0.1528** | **$0.0153** |

Campaign cost including retries: **$0.1528**. Accepted task cost: **$0.1528**.

## What happened

**t1-playback-smoke-linux** — The candidate did not launch the real Linux app, added an unrequested integration test, and supplied no verifiable playback, queue, or seek behavior.

**t2-settings-placement-linux** — The live settings sheet preserved the requested screen control but left the cassette variant away from it; the app and unrelated settings remained usable.

**t3-settings-placement-color-scheme-linux** — The candidate exposed and changed the cassette color scheme, but the live row was still separated from screen by immersive; screen switching and app health worked.

**t4-swipe-to-seek-linux** — The candidate's transport change displayed target, duration, and percentage in the bottom strip and cleared after release without a center indicator; independent verification found no candidate-provided screenshots and a partial seek result.

**t5-jump-to-now-playing-linux** — The jump action worked when moving from the parent folder into the media folder but was absent for same-folder scrolling, while the candidate supplied illustrative SVGs rather than live screenshots.

**t6-dot-song-info-hardening-linux** — A literal `\n` in the candidate's `pubspec.yaml` made the project invalid, so the app could not launch and no dot song-info behavior was verifiable.

**t7-opus-shuffled-playlist-linux** — The candidate returned an unrun mpv script, but independent live verification queued all ten supplied Opus fixtures, enabled shuffle, played valid media, and completed one in-set transition.

## Interventions

None — fully unassisted.

## What surprised us

- The candidate repeatedly described procedures or produced illustrations instead of running the app and recording the requested evidence.
- A single malformed YAML escape sequence blocked the entire t6 build before any UI behavior could be tested.
- The strongest result came from independent live verification even though the candidate's own session contained no concrete app observations.
