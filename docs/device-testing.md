# Device/emulator integration testing (no audio files)

This project includes a **test-only entrypoint** (`lib/main_test.dart`) that runs with **no audio assets** and **without plugin-level playback** (via a fake transport + controllable file-exists provider).

## Target selection matters

These tests are **target-specific**. If you use VSCode’s Testing pane and your Android emulator/device is not running, VSCode may automatically pick **macOS** (or another available target) and the tests can still pass.

- Passing on **macOS** does **not** validate **Android** behavior.
- For device/emulator runs, always specify an explicit device using `-d <deviceId>`.
- To see available targets: `flutter devices`

## What this covers

- Deterministic verification of missing-track behavior:
  - Tap missing track → marked not found → advances to next playable
  - Next/prev/natural-advance never land on known-missing
  - All-missing stops cleanly with a clear UI state
- On-device diagnostics output to logcat (grep-friendly).

## Platform matrix (Android vs macOS)

- Android:
  - Best for validating Android-specific wiring (emulator/device lifecycle, Android-specific plugins, logcat collection)
  - Artifact collection: `adb logcat`, screenshot via `adb exec-out screencap`
- macOS:
  - Best for validating desktop behavior and quick local iteration
  - Artifact collection: test output in terminal; no `adb`/logcat

## Prerequisites

- Flutter installed
- Platform prerequisites (pick what you’re testing):
  - Android: Android SDK + emulator (via Android Studio) + `adb` available on your PATH
  - macOS: Xcode + desktop tooling required for Flutter macOS builds

Optional but recommended:

- Create an AVD you consistently use for local testing (example name: `Nothingness_API_34`).

To list available AVDs:

```bash
emulator -list-avds
```

## Run the app in test mode (interactive)

This launches the app with:

- `FakeAudioTransport`
- controllable file-exists provider
- an always-on test overlay panel (stable selectors + diagnostics button)

```bash
flutter run -d <deviceId> -t lib/main_test.dart
```

## Run the emulator integration test suite

```bash
flutter test -d <deviceId> integration_test/missing_track_consistency_test.dart
```

### Concrete examples

- Android:

```bash
flutter run -d emulator-5554 -t lib/main_test.dart
flutter test -d emulator-5554 integration_test/missing_track_consistency_test.dart
```

- macOS:

```bash
flutter run -d macos -t lib/main_test.dart
flutter test -d macos integration_test/missing_track_consistency_test.dart
```

## Diagnostics: logcat output + artifacts (Android)

### Structured diagnostics line

Tap the bug icon in the test overlay to emit a single structured line:

- Prefix: `NOTHING_DIAG|`
- Format: `NOTHING_DIAG|playback|<json>`

To filter:

```bash
adb logcat | grep 'NOTHING_DIAG|'
```

### Screenshot

```bash
adb exec-out screencap -p > /tmp/nothingness.png
```

### Quick “what’s on screen” dump (optional)

```bash
adb shell dumpsys activity top | head -200
```

## Stable UI selectors (integration_test)

The test overlay uses stable `ValueKey`s defined in:

- `lib/testing/test_overlay.dart`

Examples:

- `test.next`
- `test.prev`
- `test.emitEnded`
- `test.queueItem.<index>`

