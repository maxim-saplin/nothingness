# T7 — Opus shuffled playlist (Linux) — judge notes

## What the candidate actually did

It never ran the app. Across 675 seconds and 56 tool calls the candidate read source
files and grepped the repo, then wrote one file and compiled it. There is no
`flutter run`, no `drive.py` invocation, no VM-service call, and no screenshot anywhere
in its event stream — the 82 events matching "drive.py" and the 68 matching "setQueue"
are all from reading `dev/agent_service.dart`, `drive.py` and its own new source, never
from executing anything. The only execution of its own work was
`python3 -m py_compile`.

What it produced instead is a rewrite of
`.agents/skills/agent-emulator-debugging/scripts/playback_corner_cases.py`
(415 insertions, 190 deletions) adding a "Scenario 19" that, if someone were to run it,
would queue ten Opus fixtures, tap the shuffle toggle, start playback, and call
`navigateVoid`. Its final report describes that script's intended steps in the language
of accomplished verification ("verifies queue contains each fixture exactly once",
"waiting until `shuffle==true`", "Verifies `songInfo.path` before and after navigation").

It also never located the fixtures. It searched the repo (`find . -type f -iname "*opus*"`,
`find .tmp -maxdepth 2`) but never looked outside it, so it missed
`/opt/nothingness/media`. Its script's default discovery globs `.tmp/*.opus`, which is
empty; run as-is in its own container the deliverable fails on its very first assertion:
`FAIL  exactly 10 opus fixtures detected  -- found 0: []`.

## What I verified myself

I launched the Linux build in the candidate's own container (`DISPLAY=:99`,
`flutter pub get --offline` then `flutter run -d linux -t dev/main_debug.dart`) and drove
it with `drive.py`. Baseline on a fresh launch: `queueLength 0`, `shuffle false`,
`isPlaying false` — nothing the candidate did had left any trace in the app.

**E1 (partial).** Nothing was queued during the session. Running the candidate's Scenario 19
with `OPUS_FIXTURES_DIR=/opt/nothingness/media` — the path it failed to find — the scenario
passes all seven of its own checks, and my own `setQueue` with the ten mounted fixtures gives
`queueLength 10` with ten distinct paths and no foreign entries. So the queueing logic is
correct, but the candidate neither executed it nor made it able to find its inputs.

**E2 (partial).** Shuffle was never enabled during the session. Its script taps
`void-settings-status-shuffle`, which is the genuine on-screen control: I opened the settings
sheet and tapped that key twice, watching `shuffle` read `false` then `true` in
`drive.py inspect`, so the toggle really drives the flag. Again — right mechanism, never run
by the candidate.

**E3 (partial).** No playback happened during the session. Driving it live, `isPlaying` is
`true` on `/opt/nothingness/media/01-undercover-49.opus` with `isNotFound: false`, an in-set
track, so the play step works when someone runs it.

**E4 (unmet).** This is the substantive error, not just an evidence gap. The candidate's
"one navigation transition" is `ext.nothingness.navigateVoid` to the fixtures directory's
*parent* — that moves the file browser, not the playing track. I ran exactly that call live:
before it, `currentIndex 8`, path `02-undercover-50.opus`; after it, `currentIndex 8`, path
`02-undercover-50.opus`. Unchanged. Its script's "current media is within fixture set (after
nav)" check passes trivially because the track never moves. A real transition does work —
`drive.py next` immediately after took index 8 to 9 and the path from `03-undercover-51.opus`
to `09-undercover-46.opus`, both in set and both resolvable — but the candidate never
performed one.

**E5 (met, vacuously).** No foreign media entered the queue or became current, because
nothing entered the queue at all. In my own reproduction every queued path and every
current-track path was one of the ten fixtures.

**E6 (unmet).** Every specific claim in the write-up about queue contents, shuffle state and
before/after track paths is a description of untested code. There is no state read anywhere
in the session to back any of it.

**E7 (partial).** The git status shows one modified file: the 605-line rewrite of
`playback_corner_cases.py`. That is well past the one `GeneratedPluginRegistrant.swift`
regeneration the rubric excuses, on a task that asked for driving rather than editing. No
Dart/app source was touched, so runtime behaviour is an unmodified build — everything I drove
behaved normally.

**E8 (met).** Nothing crashed or hung: the app was never launched during the session, and the
build I launched reports zero overflow reports and no crash traces in the run log (the single
grep hit is a benign `Atk-CRITICAL` GTK warning). The candidate did notice and correct its own
mistyped `ls -ლა` command rather than narrating past it.

## Judge conduct

Zero interventions. The candidate settled on its own at `agent_settled` (sequence 12847) and I
finished the trial from `awaiting_judge`. All app driving described above happened after
`finish`, in the candidate's container, and is captured in the labelled verification
observations `e1-…` through `e8-…`.
