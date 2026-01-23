# Feasibility: SoLoud Fallback for Android Opus

Date: 2026-01-19
Target: Android 12L headunit (aptiv/zeekr_dhu), app package `com.saplin.nothingness`

## Summary
- Problem: Platform playback for Opus is silent on the headunit after update; VLC works via software decode.
- Proposal: Allow an Android-only **backend toggle** to switch the playback engine to SoLoud (software decode) for **all formats**, while keeping `audio_service` for MediaSession integration.
- Outcome: Restores Opus playback reliability and provides a user-controlled fallback without breaking media session controls.

## Capabilities & Constraints
- `flutter_soloud` (v3.4.7 already in dependencies) provides cross-platform software decoding and playback. Android support is available via NDK.
- Decoding: Handles Ogg/Opus in software; outputs PCM that can be routed to Android `AudioTrack` internally.
- Integrations: `audio_service` remains the media session owner; SoLoud is only the PCM source/renderer.
- Offload: No hardware offload; CPU/battery trade-off on the SoLoud path.
- **Native libs must be packaged**: `libflutter_soloud_plugin.so` plus its deps (`libFLAC.so`, `libogg.so`, `libopus.so`, `libvorbis.so`, `libvorbisfile.so`). Packaging exclusions must not strip these.

## Selection & Guardrails (Current)
- **User toggle**: Android Settings → “SoLoud Decoder” selects the backend for all formats.
- **Startup probe**: App checks SoLoud availability on startup. If native libs are missing or SoLoud init fails, the toggle is auto-disabled and the app falls back to `just_audio`.
- **No codec auto-detection yet**: Codec probing and silent-output heuristics are deferred for now in favor of the explicit toggle.

## Fallback Integration Plan
- Transport abstraction: `AudioTransport` with `JustAudioTransport` and `SoLoudTransport` implementations.
- Switch logic:
  - **At startup**, if the Android toggle is enabled, use `SoLoudTransport` for all formats.
  - Otherwise, use `JustAudioTransport`.
- Media Session & Controls:
  - Keep `audio_service` as the single `AudioHandler` owner (`NothingAudioHandler`).
  - Media actions (`play/pause/seek/skipNext/skipPrevious`) map to the active transport.
  - Position updates flow to `audio_service` from transport events.
- Audio focus & attributes:
  - Continue using `audio_session` to request audio focus regardless of transport.
- Notifications & lockscreen:
  - No change: metadata and playback state are updated by `AudioHandler`.

## API Sketch (Minimal Changes)
- Dart: `AudioTransport` interface: `load(path)`, `play()`, `pause()`, `seek(position)`.
- `SoLoudTransport` (Android/macOS): software decode/playback, emits position/ended events.
- Controller: `NothingAudioHandler` selects transport at startup based on the Android toggle.

## Spectrum / EQ / Effects
- Spectrum: SoLoud FFT is available where wired. On Android, the current visualizer pipeline relies on a player session id (from `just_audio`); SoLoud does **not** expose a compatible session id yet, so transport spectrum may be unavailable unless wired to SoLoud FFT on Android.
- EQ: Android `Equalizer` is tied to the player session id (just_audio). On SoLoud, EQ is not applied via the platform effect unless explicitly bridged.

## Risks & Trade-offs
- CPU/Battery: Software decode consumes more CPU; acceptable for headunits, but monitor thermal.
- Latency/Seek: SoLoud seek latency may differ from ExoPlayer; validate with long Opus files.
- Feature parity: Crossfade/gapless may require extra work with SoLoud; start with parity for basic play/pause/seek.
- Library size: APK increases due to native libs.
- Maintenance: Keep a device blacklist and a runtime probe to guard against regressions.

## Testing Plan (ADB)
- Prechecks:
  - Enable the Android toggle, restart the app, and play `.opus` and `.mp3`.
  - Verify SoLoud probe logs do not show `dlopen failed`.
- Logging:
  - `adb logcat -v time | grep -i 'SoLoudTransport\|flutter_soloud\|dlopen failed'`.
  - `adb logcat -v time | grep -i 'AudioTrack\|MediaCodec\|opus'` (platform path).
- Controls:
  - Verify notification controls (prev/next/play/pause) operate SoLoud transport.
  - Check position scrubbing updates both UI and media session.
- Route/Focus:
  - Validate audio focus gain/loss events pause/resume SoLoud playback.

## Rollout Strategy
- User-controlled toggle only (no auto-detection).
- Safe fallback: If SoLoud init fails, the app auto-disables the toggle and falls back to `just_audio`.

## Work Breakdown
1. Android toggle + persistence (restart required).
2. SoLoud availability probe on startup + auto-disable on failure.
3. `SoLoudTransport` implementation and end-of-track events.
4. ADB validation on headunit; performance checks.

## Decision
Feasible with low-risk integration: reuse existing media session infra and provide a user-controlled SoLoud backend toggle on Android. This provides a reliable fallback for Opus without breaking media session controls.
