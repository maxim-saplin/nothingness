# t7-opus-shuffled-playlist-linux — judge notes

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
