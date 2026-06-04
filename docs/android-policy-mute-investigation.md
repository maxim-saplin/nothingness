# Android Policy Mute Investigation (2026-06-04)

## Scope

Goal: isolate a user-reported "silent while playing" condition without applying
fixes, and separate app-state behavior from Android policy behavior.

Method: two isolated repro angles.

1. App-state angle via VM extensions (`ext.nothingness.*`), with deterministic
   interruptions/noisy/storm command sequences.
2. Android-side angle via background key churn plus synchronized OS snapshots
   (`dumpsys` and `logcat`).

## Environment

- App: Nothingness Flutter debug build (`dev/main_debug.dart`)
- Device: `emulator-5554` (`android-x64`)
- Date: 2026-06-04

## Research Steps

### 1) App-state-only matrix

Executed sequences:

- Baseline -> play private test tone -> interruption begin/end (`pause`)
- Play -> noisy event -> explicit resume
- Interruption begin + rapid `resume/next/prev/pause/resume` storm

Observed result:

- State transitions remained coherent.
- Playback resumed after interruption end and explicit resume paths.
- No deterministic stuck-silent app-state collapse reproduced in this angle.

### 2) Android policy/service/session matrix

Executed sequences:

- Start playback.
- Background app (`KEYCODE_HOME`).
- Churn media keys (`PLAY_PAUSE`, `PLAY`, `PAUSE`).
- Capture synchronized snapshots:
  - `.tmp/dumpsys_audio_20260604_223113.txt`
  - `.tmp/dumpsys_media_session_20260604_223113.txt`
  - `.tmp/dumpsys_notification_20260604_223113.txt`
  - `.tmp/dumpsys_services_20260604_223113.txt`
  - `.tmp/logcat_20260604_223113.txt`

Observed result:

- Media session remained owned/active for `com.saplin.nothingness`.
- Foreground media notification and AudioService records were present.
- Key events were dispatched to the app media session and playback state changed.
- Audio policy history contained explicit hardening mute entries for the app:
  `AudioHardening background playback muted for com.saplin.nothingness`.

## What Was Found

1. Highest-confidence finding

Android policy/hardening mute is a credible external cause of silent-playing
incidents. Evidence exists in `dumpsys audio` history for this package.

2. What was not reproduced deterministically

The app-state machine did not collapse under isolated interruption/noisy/storm
sequences in this run.

3. Practical interpretation

The failure mode appears more likely to be cross-layer drift:

- app says "playing"
- media session may still look alive
- output is policy-muted, route-muted, or focus-constrained

## Candidate Reasons (from evidence + architecture review)

- Background hardening policy mutes (`AudioHardening`) under specific context.
- Focus/session drift after interruption storms.
- Route/device transitions not fully recovered (especially BT/noisy edges).
- Foreground-service classification gaps during rapid state churn.

## Protection Strategy (no code changes in this investigation)

- Add silent-playing watchdog: if `isPlaying` but no position or audio-energy
  progress for a window, trigger bounded recovery.
- Recovery sequence should re-establish focus, session activation, and route.
- Emit a compact incident record with:
  - focus owner/focus changes,
  - route/device state,
  - foreground-service state,
  - media session playback state,
  - transport-level progress delta.

## Components Most Likely to Be Throttled or Suspended

- Spectrum/FFT processing and other high-rate analysis loops.
- Frequent metadata/notification churn.
- Background polling/timers in UI isolate.

These should stay minimal in background paths; playback-critical behavior should
remain anchored in AudioService/transport layers.

## Conclusion

In this run, the strongest isolated lead is Android-side policy mute, not a
reproducible deterministic collapse of app playback state logic.
