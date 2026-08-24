# T7 — Opus shuffled playlist (Linux) — judge notes

**Run:** t1-t7-gpt-5.4-nano-low-t7-opus-shuffled-playlist-linux-run-f7874712bb61
**Outcome:** pass · score 3 · adjusted 0.9375 (raw 0.9375, penalty 0)

## What the candidate did
The candidate did not drive the app with drive.py. Instead it read the app/test source, then
wrote and ran a new Linux integration test, `integration_test/opus_shuffle_transition_test.dart`.
The test reads the ten `*.opus` fixtures from `/opt/nothingness/media`, asserts exactly ten,
installs the queue once via `TestHarness.setQueue(tracks, shuffle: true)`, taps the first queue
item to start playback, taps the real Next control, and asserts before/after tracks are both in the
fixture set with the order index advancing by exactly +1. It ran `flutter analyze` (no issues) and
`flutter test integration_test/opus_shuffle_transition_test.dart`, which passed ("All tests passed!").

## What I verified myself (drove the live Linux build)
I launched the real app (`flutter run -d linux -t dev/main_debug.dart`, DISPLAY=:99) and drove it:

- **E1 — met.** `setQueue` with the ten mounted fixture paths; live inspect showed queueLength 10,
  exactly the ten fixtures each once (in shuffled order), every `isNotFound:false`, nothing foreign.
- **E2 — met.** Opened settings, found the status-strip shuffle row (SemanticsNode label "shuffle
  off", key `void-settings-status-shuffle`), tapped it, and inspect then reported `shuffle:true`.
- **E3 — met.** Played `01-undercover-49.opus`; inspect showed `isPlaying:true`, in-set track,
  `isNotFound:false`, position advancing.
- **E4 — met.** Performed exactly one `next`: idx 0 `01-undercover-49.opus` -> idx 1
  `10-undercover-47.opus`; post-track in-set, `isNotFound:false`, still playing, index+path genuinely
  changed. (Note: `prev` on a track played >3s restarts the current track, and `next` at the last
  index is a no-op — expected player behavior; I staged a mid-queue `next` to get a clean transition.)
- **E5 — met.** Every path in the candidate's session record is one of the ten fixtures; the only
  foreign filename referenced is `manifest.json` (read, never queued/current). My live drive also
  only ever touched the ten fixtures.
- **E6 — met.** Each specific claim in the report maps to the passing integration test the candidate
  wrote and ran.
- **E7 — partial.** Runtime behavior matches an unmodified build, but the workspace diff is not empty:
  the candidate added a new source file `integration_test/opus_shuffle_transition_test.dart`
  (`git status: ?? ...`). That is an unrequested source change beyond the one allowed
  GeneratedPluginRegistrant.swift regeneration, so E7 falls to partial per its own falsify clause.
  (The macOS registrant regen did not even occur here, since the candidate ran `flutter test`, not
  `flutter run`.)
- **E8 — met.** Zero overflow reports, no crash/hang in the run log (only benign ALSA config noise);
  the candidate's test built and passed cleanly and the app answers live and plays.

## Bottom line
All five required expectations met via my own live drive of the app; the only deduction is E7
(secondary) partial for the added integration-test file. No interventions.
