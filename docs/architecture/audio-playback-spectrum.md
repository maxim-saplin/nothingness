# Audio Playback & Spectrum Architecture

This document details audio stack choices, data paths, and behaviors for playback-driven and microphone-driven spectrum visualization. It complements the high-level overview.

## Goals & Rationale
- Clean separation of concerns: `PlaybackController` handles business logic (user intent, queue, error recovery), `AudioTransport` provides thin native player control.
- Platform-specific transports behind one interface: SoLoud on macOS; just_audio + audio_service on Android.
- Spectrum comes from the active transport (SoLoud FFT on macOS, Android visualizer tied to player session) with microphone capture as an Android fallback.
- Preserve quick switching between transport spectrum and microphone source based on `SpectrumSettings.audioSource`.
- User intent tracking via `PlayIntent` enum prevents race conditions between pause and auto-skip.

## Core Components
- **`AudioPlayerProvider`**: `ChangeNotifier` that wraps a `PlaybackController` and surfaces state (song info, playing, queue, shuffle, spectrum data) without prop drilling.
- **`PlaybackController`**: Single source of truth for playback logic. Responsibilities include:
  - **User intent tracking**: Maintains `PlayIntent` enum (play/pause) to represent explicit user intent, preventing race conditions between pause and auto-skip.
  - **Queue management**: Owns `PlaylistStore` instance, manages track ordering, shuffle state, and current index.
  - **Error recovery policy**: Listens to transport error events, checks `userIntent` before deciding to skip or stay paused. If `userIntent == play` and error occurs → skip to next; if `userIntent == pause` → stay paused.
  - **`isNotFound` tracking**: Backend-agnostic tracking of failed track paths (moved from platform-specific implementations).
  - **SongInfo emission**: Consolidates song info updates from transport position/duration.
- **`AudioTransport` (interface)**: Thin abstraction over platform-specific players. Provides minimal interface:
  - Load audio files (`load(String path)`)
  - Play/pause/seek control
  - Position and duration queries
  - Event emission (`TransportEvent`: error, ended, loaded, position)
  - Spectrum stream (optional)
  - Does NOT handle: queue management, skip logic, user intent tracking
- **`AudioTransport` implementations**:
  - **`SoLoudTransport` (macOS)**: Thin wrapper around SoLoud for playback and FFT. No queue awareness, no skip logic.
  - **`JustAudioTransport` (Android)**: Thin wrapper around just_audio + audio_service/just_audio_background for playback, media session, notification, headset/lock-screen controls. Spectrum via Android visualizer bound to the player session. No `maxSkipsOnError` - all skipping handled by `PlaybackController`. Android package is arm64-only and excludes SoLoud native libs.
- **`SpectrumProvider` interface**: Strategy for sourcing FFT bars.
  - **Transport spectrum**: SoLoud FFT (macOS) or Android visualizer stream.
  - **`MicrophoneSpectrumProvider`** (Android fallback): Streams FFT bars from native `AudioCaptureService` via EventChannel; requires mic permission.
- **`MediaControllerPage`**: Uses Provider for player state; switches capture based on `SpectrumSettings.audioSource` (transport spectrum by default, mic when explicitly selected on Android).

## Playback Pipeline (Transport Spectrum)
```mermaid
flowchart LR
  UI[MediaControllerPage] -->|watch| Provider[AudioPlayerProvider]
  Provider -->|play/enqueue/seek| Controller[PlaybackController]
  Controller -->|load/play/pause/seek| Transport[AudioTransport]
    Transport -->|macOS| SoLoud[SoLoudTransport]
    Transport -->|Android| JA[JustAudioTransport]
    SoLoud -->|PCM + FFT| Vis[SpectrumVisualizer]
    JA -->|sessionId| Native[Android Visualizer]
    Native -->|FFT bars| Vis
    Controller -->|userIntent error recovery| Transport
```

### Lifecycle Notes
- Transports and controller initialize at bootstrap via `AudioPlayerProvider.init()` → `PlaybackController.init()` → `AudioTransport.init()`; macOS enables SoLoud visualization, Android binds to the player session for visualizer once sources are set.
- On play: `PlaybackController` sets `userIntent = PlayIntent.play`, transport stops prior playback/source, loads, plays, and (re)starts spectrum capture (SoLoud FFT or Android visualizer subscription).
- On pause: `PlaybackController` sets `userIntent = PlayIntent.pause`, transport pauses playback and stops spectrum capture to reduce CPU; resume restarts capture. Error recovery respects `userIntent` - if paused, errors don't trigger auto-skip.
- On completion: Transport emits `TransportEndedEvent`; `PlaybackController` checks `userIntent` and advances to next track if `userIntent == play`, otherwise stops.
- On error: Transport emits `TransportErrorEvent`; `PlaybackController` marks track as `isNotFound`, checks `userIntent`, and skips only if `userIntent == play`. All skip logic handled in Dart, no native `maxSkipsOnError`.

## Microphone Pipeline (Android Only, fallback)
```mermaid
flowchart LR
    UI -->|audioSource: microphone| Platform[PlatformChannels]
    Platform -->|EventChannel bars| Visualizer
    Native[AudioCaptureService] -->|FFT bars| Platform
```

### Lifecycle Notes
- Requires notification/audio capture permissions.
- Switching to mic mode stops transport spectrum and subscribes to the native mic stream.
- Switching back to transport mode re-enables transport spectrum (SoLoud FFT or Android visualizer).

## Settings Impact
- `SpectrumSettings.audioSource`: toggles transport spectrum (default) vs mic provider (Android-only fallback).
- `SpectrumSettings.barCount`, `decaySpeed`, `noiseGateDb`: applied in spectrum providers; decay also maps to transport FFT/visualizer smoothing when supported.
- Settings load after transport/controller init to avoid init races and are pushed to transports and native side as needed.

## Playlist Management
- Queue state (tracks, play order, current index, shuffle flag) is persisted with Hive via `PlaylistStore`, sized to handle thousands of tracks efficiently.
- The "Now Playing" tab renders the active play order; tapping shuffle reshuffles and keeps the current track first, and reset order restores sequential playback.
- Auto-advance uses the persisted play order; when the queue ends playback stops cleanly while keeping the queue available on next launch.

## Error Handling & Guardrails
- SoLoud init is awaited before visualization calls; UI bootstrap was sequenced to remove `SoLoudNotInitializedException` risk.
- **Error Recovery Policy**: `PlaybackController` listens to `TransportErrorEvent` from transports. When an error occurs:
  - Track path is marked as `isNotFound` (backend-agnostic, stored in controller's `_failedTrackPaths` set)
  - Controller checks `userIntent`:
    - If `userIntent == PlayIntent.play`: Automatically skips to next track
    - If `userIntent == PlayIntent.pause`: Stays paused, does not skip (prevents race conditions)
  - All skip logic handled in Dart; no native `maxSkipsOnError` in transports
- **User Intent Tracking**: `PlayIntent` enum prevents race conditions. When user pauses, `userIntent = PlayIntent.pause` is set explicitly. If transport auto-skips due to error, controller checks intent before deciding to skip, ensuring user's pause intent is respected.
- Transport load/play errors are caught and emitted as `TransportErrorEvent`; controller handles recovery based on user intent.
- Spectrum polling checks for a valid handle and skips if absent.
- Source disposal happens before new loads to prevent leaked handles.
- Mic pipeline activates only when permission is granted; otherwise bars fall back to zeros.

## Known Limitations / Future Work
- macOS: spectrum is player-only; no microphone capture path.
- SoLoud visualization must remain enabled; providers re-enable on start if needed.
- Android package is arm64-only; adding more ABIs would increase APK size.
- Consider graceful backoff/logging when native mic stream stalls.
- Possible enhancement: normalize FFT window size to match bar count more tightly.

## References
- High-level overview: [overview.md](overview.md)
- UI scaling details: [ui-scaling.md](ui-scaling.md)
- Skins/layouts: [skins.md](skins.md)
