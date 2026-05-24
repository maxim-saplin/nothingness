# Backlog

Single-file issue tracker for in-flight UX/bug work on `main`. Continues the
`B-NNN` numbering from the closed `ui-revamp` arc (last id was B-010).

## Conventions

- One H2 per issue: `## B-0NN (severity): title` — severity is `minor` /
  `major` / `blocker`.
- Body uses these fields (omit any that don't apply):
  - **Symptom** — what the user observes.
  - **Repro** — exact sequence (driver commands welcome) plus the runtime
    evidence we collected (numbers, screenshots, logcat snips).
  - **Desired** — what we want it to do.
  - **Notes** — code pointers (`path/to/file.dart:line`), constraints,
    cross-refs (`see B-0NN`).
  - **Area** — short tag (`chrome`, `search`, `transport`, `permissions`,
    `browser`, `heroes`, `settings`).
- When an item is fixed, **move the entry to `backlog_done.md`** and append
  a `**Closed**: YYYY-MM-DD — one-line summary of the resolution (commit
  hash if useful)` line at the bottom of the moved entry. Keep the trail —
  it's cheap to read and pays off when a regression looks familiar.
- New ids are assigned monotonically across both files. Don't reuse closed
  ids; check `backlog_done.md` too when picking the next id.

---

## B-008 (minor): Choreographer skips ~140 frames at cold launch

**Symptom**: First frame logs `Choreographer: Skipped 140 frames` — cold
launch is visibly janky on slower devices.

**Cause**: Sequential bootstrap before `runApp` (settings load, audio
session init, SoLoud init) runs on the platform thread, starving frame
production.

**Desired**: Defer non-essential init behind a post-frame callback or a
splash widget so the first frame paints before settings/audio init
completes. Acceptable to show a black void for ~one frame.

**Area**: bootstrap / chrome

**Investigation 2026-05-24**: Tried moving `LibraryService.init`,
`AudioService.init`, and `AudioPlayerProvider.init` behind a post-frame
callback in `_NothingAppState.initState`. 5-run paired comparison on
emulator-5554 (debug, x86_64):

- Baseline-A first-skip [30, 77, 33, 33, 75]; second-skip [184, 168, 174, 160, 153].
- Post-fix first-skip [164, 136, 135, 36, 35] / [129, 139, 180]; second-skip [188, 174, 209, 290, 256].
- Baseline-B (rebuild): first-skip [37, 165, 137, 130, 195]; second-skip [294, 186, 177, 207, 188].
- `Displayed`: ~8s on every variant.

Run-to-run variance on nominally identical baseline builds exceeds the
delta between baseline and post-fix. `runApp` is synchronous after the
deferral, but `AudioService.init` still blocks the platform thread when
it runs post-frame, so total skipped-frame count and time-to-Displayed
do not measurably improve. Working tree restored to clean; no commit
landed.

Real wins likely require: (a) push `AudioService.init` off the platform
thread (upstream `audio_service` plugin change), (b) a splash widget that
keeps the engine in cheap-render mode until init returns, or (c) measure
on real hardware where emulator JIT warmup doesn't dominate. The second
skip-burst (~170-290 frames) is probably `flutter_soloud` native init,
not `audio_service` — worth isolating before another attempt.

---

## B-011 (major): Play/pause feels delayed on Android

**Symptom**: Tapping play/pause (hero or transport row) takes ~half a second
to start audio. With no visual confirmation (see B-012) the gesture reads as
ignored.

**Repro**: On emulator-5554 (x86_64, debug):
```
.../drive.py pause; sleep 1; .../drive.py resume
```
Logcat shows `MediaSessionService onSessionPlaybackStateChanged …
state=PLAYING` ≈ 500 ms after the RPC fires. RPC itself (`drive.py resume`,
which mirrors what an in-app `playPause()` does on Android) returns in
~500–700 ms across three runs. Optimistic UI flip is already in place
(`PlaybackController.playPause` at
`lib/services/playback_controller.dart:464,469`), so the lag the user feels
is the AudioHandler → AudioService → SoLoud chain, not the Dart state.

**Desired**: Profile each hop (`NothingAudioHandler.onPlay`,
`audio_service` plugin glue, native `AudioFocus`, SoLoud `play`) and shrink
whichever dominates. If the chain is irreducible, lean on B-012 to mask the
gap.

**Notes**: Cross-ref B-012 (visual feedback) and B-018 (per-skin transport).

**Area**: transport / playback
