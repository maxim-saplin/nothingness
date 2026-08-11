# T7 · Opus shuffled playlist (Linux) — judge notes

Run: `t1-t7-gpt-5.4-nano-medium-t7-opus-shuffled-playlist-linux-trial-01-attempt-03`
Model: gpt-5.4-nano, thinking medium. Judge: judge-t7. Interventions: 0.
Outcome: **pass** (band 3, raw 1.0, adjusted 1.0). Candidate settled on its own at 540s of a
1200s budget, 62 tool calls, $0.060.

## What the candidate actually did

It spent the first ~3 minutes reading, not driving: `drive.py`, `dev/agent_service.dart`, the
regression README, and the extension handler table, to find out how `setQueue`, the shuffle toggle
and `next` are actually wired. Then it ran `drive.py preflight`, saw no live VM, launched the Linux
build (`flutter pub get` then `flutter run` under `DRIVE_TARGET=linux`), waited out the ~3-minute
SoLoud/CMake build, and confirmed `live VM=yes` before touching anything.

The working sequence was short and correct:

1. `drive.py call ext.nothingness.setQueue paths="$(ls -1 /opt/nothingness/media/*.opus | sort | paste -sd, -)" startIndex=0` → `{"queued": 10}`. It built the path list from the mount rather than typing names, so there was no chance of a typo or an eleventh file.
2. `getPlaybackState` → `queueLength 10`, the ten fixtures in sorted order each once, `isNotFound false` on all, `isPlaying true`, `currentIndex 0` on `01-undercover-49.opus` at position 5.3s. Note that `setQueue` starts playback itself, which is why the candidate never needed a separate `play` call — "play valid supplied media" was satisfied by real audio actually running (`spectrumNonZero: true`).
3. `drive.py settings open`, then `drive.py tap void-settings-status-shuffle` → `{"tapped": ..., "mode": "descendant-callback"}`. The follow-up `getPlaybackState` read `shuffle: true` with the queue genuinely re-permuted and the current track carried to its new index 6, still playing `01-undercover-49.opus`.
4. Captured "before" (`01-undercover-49.opus`), ran `drive.py next` **once**, then polled `getPlaybackState` until the path changed — it had already changed on the first poll to `09-undercover-46.opus`. A final read confirmed `currentIndex 7`, `isPlaying true`, queue still the ten fixtures.
5. It then re-asserted the whole thing in an inline Python check over the live state (queue length 10, 10 unique, set equality against `glob('/opt/nothingness/media/*.opus')`, before/after both in-set and distinct) → `queue_ok`, `transition_ok`, and wrote a replay script recording the exact sequence.

Exactly one transition happened in the entire session: one `next`, zero `prev`, one `setQueue`, zero
`play`. Nothing had to be walked back.

## What I verified with my own hands

The candidate left the app running, so I drove its own live session rather than a replacement — my
first capture found it still playing `09-undercover-46.opus` at 249s of 359s, i.e. the very track its
`next` had selected, continuing uninterrupted (`verification-c21fef32f7ff44c3a89d973333c3cfc6`).

- **E1 met.** I re-ran `setQueue` with the ten mounted paths myself and read the runtime lens: `queueLength 10`, the ten fixture paths each exactly once, nothing foreign, `isNotFound false` throughout (`verification-7761904a3cc849b2a8c4036a86e75b3c`).
- **E2 met.** I did not take the flag on trust. With the sheet open I tapped `void-settings-status-shuffle` and watched `shuffle` go **true → false** (`verification-f27d4b971aa34264966af7032258a1f2`), then tapped the same row again and watched it go **false → true**, with the queue re-permuted into a different order than the candidate's while the current track was preserved (`verification-49fd97a169b4425a968a0b98bda0e83a`). The on-screen control is what moves the flag.
- **E3 met.** I closed the sheet, ran `drive.py play /opt/nothingness/media/05-undercover-53.opus`, and captured `isPlaying true`, current path in-set, `isNotFound false`, position advancing (`verification-d24a8e232bec449e8e6b53800ac3b030`).
- **E4 met.** One `drive.py next` moved current from `05-undercover-53.opus` (index 5) to `06-undercover-54.opus` (index 6), still playing, still `isNotFound false`, both endpoints in the fixture set (`verification-714fffddd86e408aa6d13a7875db0943`). A real transition, not a no-op.
- **E5 met.** I scanned the entire session record for audio paths. Every distinct `"path"` value in every playback-state dump is one of the ten fixtures. The only non-fixture audio *filenames* anywhere in the transcript (`t1_a440_2s.wav`, `long_10s.wav`, `/absolute/path/foo.mp3`) come from documentation and existing replay scripts the candidate read; none was ever queued or made current.
- **E6 met.** Each claim in the final report maps to a concrete read: the queue claim to the post-`setQueue` dump plus its own set-equality assertion; `shuffle: true` to the post-tap dump; the before/after paths to the two reads bracketing the single `next`; the replay-script claim to the write itself. No claim rests on memory.
- **E7 met.** `candidate.diff` is 0 bytes and the inspection's git lens shows an empty `diff_stat` — this run did not even produce the tolerated `GeneratedPluginRegistrant.swift` regeneration. The one workspace addition is a single untracked file, `tool/regression/opus_fixtures_shuffle_next.txt`, a `drive.py replay` script that documents the sequence; it changes no app code, no setting, and no runtime behaviour, and my re-derivation of queue/shuffle/play/next behaved exactly like a stock build.
- **E8 met.** Nothing broke that needed recovering: `overflows` count 0 in every capture, and the run log (270 lines) has no lost-connection, `EXCEPTION CAUGHT` or segfault traces. Three tool calls did fail — two `grep` invocations that matched nothing (it used `|` alternation without `-E`), and one `python3 - <<'PY'` heredoc that swallowed stdin so `json.load(sys.stdin)` got the script instead of the piped state. The candidate diagnosed that last one correctly, re-ran it by writing state to `/tmp/playback_state.json` first, and got its assertions to pass. It fixed its own tooling rather than reporting over the failure.

## Worth noting

- `playTrackByPath` (what `drive.py play` uses) sets the current track without syncing `currentIndex` to that track's queue position: after I played `05-undercover-53.opus` (queue position 3), `currentIndex` still read 5, so my `next` advanced to index 6 rather than index 4. Pre-existing fixture behaviour, unrelated to the candidate, and it does not affect any expectation here — the transition was still genuine and in-set.
- The candidate's "after" detection loop assigned to the shell variable `PATH`, which would have broken subsequent lookups inside that loop had it needed a second iteration. It matched on the first poll, so nothing came of it.
- This was attempt 03 of trial 1; the earlier attempts are not part of this scoring.
