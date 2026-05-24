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

## B-021 (minor): `requestLibraryPermission` side-channel bundles mic+storage

**Symptom**: After B-017 the production OWN-mode gate is audio-only, but
the QA-only `ext.nothingness.requestLibraryPermission` extension still
calls a list that includes `Permission.microphone` and `Permission.storage`.
QA runs that trigger it see misleading 3-permission dialogs and report
spurious mic prompts.

**Desired**: Drop mic and storage from the side-channel's request list in
`lib/testing/agent_service.dart`. The probe should mirror the production
controller (`LibraryController.requestPermission` → audio-only) so QA
runs see the same gate the user sees.

**Notes**: Surfaced during B-017 QA. The production path is correct; only
the test-extension probe drifted.

**Area**: testing / agent-service

---

## B-022 (minor): `setSetting` has no `transport` case

**Symptom**: `ext.nothingness.setSetting` switches `screen`,
`themeVariant`, `operatingMode`, `fullScreen`, `debugLayout`, `uiScale`,
`immersive` — but **not** `transport`. Driving transport position
(top/bottom/off) from the agent requires writing the underlying
SharedPreferences key + a `restart`, which is two extra hops.

**Repro**: B-018 smoke test required this; QA fell back to settings-sheet
tap, which only works when the sheet isn't blocked by F-024.

**Desired**: Add a `transport` case to the switch in `_setSetting`
(`lib/testing/agent_service.dart`). Route it through the same notifier
the in-app settings UI uses for the transport row, so changes propagate
live without restart.

**Area**: testing / agent-service

---

## B-023 (minor): `screen` setSetting clobbers per-skin configs

**Symptom**: `ext.nothingness.setSetting name=screen value=dot` (or any
hero) constructs `const DotScreenConfig()` (and equivalent for other
heroes), discarding any persisted per-skin settings — including B-020's
`showSongInfo`. After a `screen` swap via the agent, the active config
is whatever the constructor literal says, not what's on disk.

**Repro**: surfaced during B-020 QA when toggling `showSongInfo` via
preference then `screen dot` reset it back to default false.

**Desired**: The `screen` case should change the active screen identity
without recreating the screen's config from scratch. Load the persisted
config (or the in-memory one if already loaded) and reapply.

**Notes**: `lib/testing/agent_service.dart` around the `screen` case in
`_setSetting`. Should reuse whatever load path `main.dart` uses on
startup.

**Area**: testing / agent-service

---

## B-024 (minor): `openSettingsSheet` extension hangs the RPC

**Symptom**: `ext.nothingness.openSettingsSheet` awaits
`Navigator.push(...)`. `push` does not complete until the route pops, so
the VM-service call never returns. `drive.py settings open` times out
even though the sheet IS visible on the device.

**Repro**: noticed in B-007 QA (benign stderr leak) and re-confirmed in
B-020 implementer work (forced a tooling workaround).

**Desired**: Detach the push from the await. `unawaited(Navigator.push(...))`
returns immediately, while the route is still scheduled. The extension's
response payload (`{"opened": true}`) can fire right after `push` is
called.

**Area**: testing / agent-service

---

## B-025 (minor): `tapByKey` requires the keyed widget to handle the tap

**Symptom**: `ext.nothingness.tapByKey` walks the widget tree for a
`ValueKey<String>` match and then looks for a `GestureDetector` /
`InkResponse` at that node. B-012's `_TouchDownDimmer` carries the
`void-settings-…` keys but the gesture handler is a descendant
(`GestureDetector` inside the dimmer); `tap` errors `no tappable
ancestor`.

**Repro**: B-012 QA hit this trying `drive.py tap transport-play`.
Workaround was raw `adb input tap` at coordinates.

**Desired**: Locate the keyed widget's `RenderBox` and dispatch a
synthetic tap event at its center via `GestureBinding.instance`. This
keeps `ValueKey` as the addressing scheme while letting the actual
gesture handler be anywhere in the descendant subtree.

**Area**: testing / agent-service

---

## B-026 (minor): Spectrum sub-pixel overflow at uiScale=2.5

**Symptom**: At `uiScale=2.5` on Spectrum, a RenderFlex reports a 0.453 px
overflow. Visually negligible but noisy in logs and a latent bug if
the rounding error grows on different devices.

**Repro**: `drive.py call ext.nothingness.setSetting name=uiScale value=2.5`,
`drive.py screen spectrum`. `drive.py overflows` (or check logcat) reports
the 0.453 px overflow. At `uiScale=1.0` no overflow.

**Desired**: Find the offending RenderFlex (probably the Spectrum hero's
song-info column) and either wrap the inner child with `Flexible`/
`Expanded`, add `mainAxisSize: MainAxisSize.min`, or round the affected
size up via `ceil`/`floor`. Sub-pixel-stable layout.

**Notes**: Surfaced during B-019 and B-018 QA — not introduced by either.
Pre-existing; would have been a tip-of-iceberg if the rounding grew.

**Area**: heroes / spectrum

---

## B-027 (minor): Hero swipe misses fast-but-short flicks

**Symptom**: B-012 added a 60-dp horizontal-drag accumulator on the hero
to fire prev/next. A short fast flick (e.g. 40 dp in 80 ms) never crosses
the distance threshold and silently does nothing — even though the user
clearly intended a swipe.

**Repro**: `adb shell input swipe 200 1200 350 1200 80` on Spectrum.
Distance 150 px ≈ 50 dp at 1× density. Accumulator never crosses 60 dp.
Compare with PageView's swipe: also tracks velocity, fires when either
distance OR velocity threshold passes.

**Desired**: In the hero's horizontal drag handler, also track the final
velocity. If velocity at end exceeds ~300 dp/s (tune to feel), fire
prev/next even when distance is under 60 dp. Direction is sign of
velocity.

**Notes**: Implementer of B-012 flagged this as a separate ticket. Look
at `lib/widgets/hero_feedback_surface.dart` and the gesture wiring in
`lib/screens/void_screen.dart`.

**Area**: chrome / heroes / transport
