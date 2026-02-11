# SoLoud: Single Playback Backend on Android

Date: 2026-01-19 (original); updated 2026-02-11
Target: Android 12L headunit (aptiv/zeekr_dhu), app package `com.saplin.nothingness`

## Summary
SoLoud (`flutter_soloud` v3.4.7) is the sole playback backend on all platforms (Android + macOS). The previous `just_audio` backend and Android toggle have been removed as part of the single-backend simplification.

## Architecture
- `SoLoudTransport` implements `AudioTransport` and handles software decoding/playback for all audio formats.
- `NothingAudioHandler` (audio_service) owns MediaSession/notification state and delegates to `PlaybackController` which uses `SoLoudTransport`.
- Spectrum visualization uses SoLoud's built-in FFT, streamed via `NothingAudioHandler.spectrumStream` → `AudioPlayerProvider`.
- Microphone spectrum capture remains available via native `AudioCaptureService` and platform channels.

## Native Libraries
`libflutter_soloud_plugin.so` plus dependencies (`libFLAC.so`, `libogg.so`, `libopus.so`, `libvorbis.so`, `libvorbisfile.so`) must be packaged in the APK. Packaging exclusions must not strip these.

## Known Limitations
- **No hardware offload**: SoLoud uses software decoding; higher CPU/battery usage. Acceptable for headunit target.
- **EQ disabled**: Platform `android.media.audiofx.Equalizer` required a just_audio session id. A SoLoud filter-based EQ is planned.
- **Android package is arm64-only**.

## Testing
- Verify SoLoud probe at startup; show error dialog if native libs missing.
- Validate notification controls (prev/next/play/pause) work via `audio_service`.
- Confirm spectrum visualization animates from SoLoud FFT.
- Confirm mic spectrum still works when switching audio source.
