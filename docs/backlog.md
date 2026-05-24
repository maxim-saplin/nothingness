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

## B-028 (minor): Per-screen `screen_config` persistence

**Symptom**: Settings persistence uses a single `screen_config`
SharedPreferences key holding the active screen's config blob. When the
agent (or user) swaps from Dot → Spectrum → Dot, the Dot config is
overwritten with Spectrum's blob during the middle step, so the second
Dot switch loses any non-default fields (e.g. `showSongInfo` from B-020).

**Repro**: surfaced during B-023 QA. Set Dot `showSongInfo=true`; switch
to Spectrum via `ext.nothingness.setSetting name=screen value=spectrum`;
switch back to Dot. The `showSongInfo=true` is gone.

**Desired**: Persist per-screen configs under separate keys
(`screen_config_dot`, `screen_config_spectrum`, `screen_config_polo`,
`screen_config_void`). On `screen` swap, write the OUTGOING screen's
config to its own key, read the INCOMING screen's persisted config (or
default) from its key. Migration: on first read after upgrade, if the
old `screen_config` key still exists, parse its `screenId` and write
the blob to the matching per-screen key, then delete the old key.

**Notes**: Look at `lib/services/settings_service.dart` for the current
load/save paths. B-023's `_resolveScreenConfig` already has a live-
notifier shortcut + persisted-JSON reload — the new keys plug in below
that. Keep the migration small and idempotent.

**Area**: settings / persistence

---

## B-029 (minor): `drive.py reset` kills the live `flutter run`

**Symptom**: `drive.py reset` internally calls
`adb shell am force-stop com.saplin.nothingness` + `pm clear`, which
crashes any attached `flutter run` session with `Lost connection to
device` and forces a 60-90 s rebuild. The SKILL.md note added for
B-021..B-025 warns about `force-stop` and `pm revoke RECORD_AUDIO` but
does not name `reset` directly, so an agent reading the skill can
trigger the hazard via the wrapper without noticing.

**Repro**: surfaced during B-027 implementer work. With flutter run
attached, running `drive.py reset` ended the session and the running
APK reverted to the pre-fix binary.

**Desired**:
1. Update `drive.py reset` to detect a live flutter run session (check
   `/tmp/flutter_run.log` mtime + VM service responding via the cached
   WS URI). If alive, refuse with a clear message; accept `--force` to
   override.
2. Update `.claude/skills/agent-emulator-debugging/SKILL.md` to:
   - Name `drive.py reset` explicitly in the "Do not kill the live
     flutter run" note (point at the `--force` flag).
   - Add a short note that **ADB synthetic-event swipes do not reliably
     hit Flutter's velocity thresholds**, so hero/swipe gestures should
     be verified with `tester.fling` in widget tests rather than chased
     via `adb shell input swipe X1 Y X2 Y duration` (surfaced during
     B-027 live verification).

**Area**: testing / agent-skill / drive
