# Single Backend Simplification: SoLoud-Only

Date: 2026-02-11
Owner: Nothingness

## Problem Summary
The codebase maintains two playback backends (`just_audio` / `SoLoud`) on Android with a user-facing toggle, plus all the glue to route spectrum, EQ, and session ids conditionally. SoLoud now integrates fully into Android's media system (MediaSession, notifications, background play, spectrum), making the dual-backend architecture unnecessary maintenance burden.

## Goals
- Make SoLoud the single playback backend on all platforms.
- Remove `just_audio`, `just_audio_background` dependencies.
- Delete dead code paths: `JustAudioTransport`, `JustAudioBackend`, `SoloudSpectrumBridge`, `VisualizerService`, backend toggle, sessionId routing.
- Simplify `AudioPlayerProvider` and `NothingAudioHandler` to a single unconditional path.
- Reduce total codebase by ~800-1000 lines of Dart + Kotlin.

## Non-Goals
- Adding new features (crossfade, gapless, codec detection).
- Rewriting the EQ on SoLoud filters (separate follow-up; see Open Questions).
- Changing macOS behavior (already SoLoud-only).

## What Gets Removed

| File / Component | Action | LOC (approx) |
|------------------|--------|---------------|
| `lib/services/just_audio_transport.dart` | Delete | ~200 |
| `lib/services/just_audio_backend.dart` | Delete | ~450 |
| `lib/services/audio_backend.dart` | Delete (interface) | ~40 |
| `lib/services/soloud_spectrum_bridge.dart` | Delete (no longer needed) | ~55 |
| `test/services/soloud_spectrum_bridge_test.dart` | Delete | ~65 |
| `android/.../VisualizerService.kt` | Delete | ~100 |
| `SettingsService.androidSoloudDecoderNotifier` | Remove toggle + persistence | ~15 |
| `AudioPlayerProvider` dual spectrum routing | Simplify | ~60 net |
| `NothingAudioHandler` sessionId/backend branches | Simplify | ~40 net |
| `main.dart` probe/toggle logic | Simplify | ~15 |
| `pubspec.yaml` just_audio deps | Remove 2 deps | — |

## What Gets Simplified

### `NothingAudioHandler`
- Always create `SoLoudTransport`. Remove `useSoloud` param.
- Remove `isSoloudBackend`, `androidAudioSessionId`, sessionId stream forwarding.
- Remove `'backend'` and `'sessionId'` custom events.
- Expose `spectrumStream`, `setCaptureEnabled`, `updateSpectrumSettings` directly (already done).

### `AudioPlayerProvider`
- Remove `_androidSessionId`, `_isSoloudActive`, `_soloudSpectrumBridge`.
- Remove `_androidCustomEventSub` listener for `sessionId`/`backend` events.
- `_maybeStartAndroidSpectrum` → subscribe directly to `handler.spectrumStream`. One path.
- `setCaptureEnabled` → forward to `handler.setCaptureEnabled()`. No branching.
- `updateSpectrumSettings` → forward to handler. No `_platformChannels.updateSpectrumSettings` for player spectrum.
- `supportedExtensions` → always `SoLoudTransport.supportedExtensions`.
- Remove `JustAudioTransport` import and fallback constructor branch.

### `main.dart`
- Remove `androidSoloudDecoderNotifier` check, `SoLoudTransport.probeAvailable()` probe, and auto-disable logic.
- Always pass `NothingAudioHandler()` (no `useSoloud` flag).
- Keep `AudioService.init` wrapper for MediaSession.

### `PlatformChannels`
- `spectrumStream(sessionId:)` — keep for mic-only path (sessionId=null means mic). Remove sessionId-based Visualizer path.
- `setEqualizerSessionId` — remove or no-op (EQ disabled until SoLoud filter rewrite).
- `updateEqualizerSettings` — remove or no-op.

### Android Kotlin (`MainActivity.kt`)
- Remove `VisualizerService` usage and the sessionId-based `startSpectrumCapture` branch.
- Keep `AudioCaptureService` for mic spectrum.
- Remove or stub EQ methods (`setEqualizerSession`, `applyEqSettings`, `releaseEqualizer`).

### Settings UI
- Remove "SoLoud Decoder" toggle from settings screen.
- Remove or disable EQ UI (or show "EQ not available" until SoLoud filter rewrite).

## Implementation Steps

### Phase 1: Core backend unification (Dart)
1. `NothingAudioHandler`: remove `useSoloud` param, always create `SoLoudTransport`. Remove sessionId/backend event logic.
2. `AudioPlayerProvider`: remove dual spectrum routing. Subscribe to `handler.spectrumStream` directly for player spectrum on Android.
3. `main.dart`: remove probe/toggle logic.
4. `SettingsService`: remove `androidSoloudDecoderNotifier`, `_androidSoloudDecoderKey`, `setAndroidSoloudDecoder`.
5. Delete `JustAudioTransport`, `JustAudioBackend`, `AudioBackend`, `SoloudSpectrumBridge`.
6. Delete `test/services/soloud_spectrum_bridge_test.dart`.
7. Update `PlaybackController.supportedExtensions` to remove `JustAudioTransport` branch.

### Phase 2: Native cleanup (Kotlin)
8. Delete `VisualizerService.kt`.
9. `MainActivity.kt`: remove Visualizer-based spectrum path, remove/stub EQ methods.
10. Keep mic-based `AudioCaptureService` and its EventChannel intact.

### Phase 3: Dependencies
11. Remove `just_audio` and `just_audio_background` from `pubspec.yaml`.
12. Run `flutter pub get` to verify clean resolution.

### Phase 4: Settings UI
13. Remove "SoLoud Decoder" toggle from settings screen.
14. Remove or disable EQ settings UI.

### Phase 5: Docs & tests
15. Update `docs/architecture/audio-playback-spectrum.md` — single backend, no dual routing.
16. Update `docs/soloud-android-fallback.md` — rename/revise to reflect SoLoud is now the only backend, not a fallback.
17. Update `docs/README.md` index.
18. Run `flutter analyze`, `flutter test`, verify on emulator.
19. Bump version, commit.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| SoLoud native libs missing on some builds | App won't play audio | Keep `SoLoudTransport.probeAvailable()` at startup; show error dialog instead of silent failure |
| `content://` URIs from file picker | SoLoud needs filesystem paths | Audit file picker usage; if content URIs are used, add temp-file copy layer |
| EQ removed | Users lose equalizer | Document as known limitation; follow-up with SoLoud filter-based EQ |
| CPU/battery on phones | Software decode is heavier | Acceptable for target use case (headunits); note in docs |
| Mic spectrum regression | Mic path shares `PlatformChannels` code | Keep `AudioCaptureService` and mic EventChannel paths unchanged |

## Verification Plan
- `flutter analyze` clean.
- `flutter test` all pass.
- Emulator: play track → spectrum animates (SoLoud FFT).
- Emulator: switch to mic source → mic spectrum works.
- Emulator: media notification controls (play/pause/next/prev) work.
- Emulator: background playback continues.
- Emulator: EQ UI removed or shows disabled state.
- macOS: no behavioral change (already SoLoud-only).

## Open Questions
- **EQ follow-up**: Rewrite Android EQ using `SoLoud.addGlobalFilter()` (biquad resonant filter)? Separate task or bundle here?
- **`content://` URI audit**: Does the file picker ever return content URIs, or always filesystem paths? If content URIs exist, need a copy-to-temp adapter.
- **Remove `just_audio_backend.dart` references in settings UI**: Any UI that mentions "just_audio" or "platform decoder"?
