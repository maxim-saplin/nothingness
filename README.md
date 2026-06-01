# Nothingness – Retro Audio Player & Spectrum Visualizer

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/maxim-saplin/nothingness)](https://github.com/maxim-saplin/nothingness/releases/latest)

Nothingness is a **fully-fledged audio player** and **retro spectrum visualizer** for Android and macOS. It plays your local music library while rendering a pixelated, 80s‑style spectrum analyzer driven directly by the audio playback.

Originally inspired by a need for digital minimalism in modern cars (specifically the Zeekr infotainment system), it features a **Global UI Scaling** engine that adapts the interface to any screen DPI, making it perfect for car dashboards, tablets, and desktops.

<img width="300" alt="image" src="https://github.com/user-attachments/assets/24d3f16d-4a7e-473a-8c77-4b4922c2d404" />

## Features

### 🎵 Audio Player
-   **Local Playback**: Plays audio files from your device's storage.
-   **Library Management**:
    -   **Folder Picker**: Select folders to play.
    -   **Recursive Enqueue**: "Play All" adds all tracks in a folder and its subfolders.
    -   **Queue Control**: Reorder, remove, and manage your Now Playing queue.
    -   **Global Search**: Type-ahead match across the entire library. Tapping a result installs the result list as a temporary sub-queue and restores the original queue when you dismiss search.
    -   **Jump to Now-Playing**: A glyph appears in the path crumb whenever the browser is in a different folder than the playing track; tap to teleport the browser there (opens it first if currently dismissed) and center the row.
-   **Platform Integration**:
    -   **Android**: Full media session support, background playback, lock screen controls, and notification controls. Cached audio-session avoids redundant focus IPC on every play/pause — sub-150 ms transport response in the common case.
    -   **macOS**: Native playback via SoLoud.

### 📊 Spectrum Visualizer
-   **Playback-Driven**: Visualizer reacts directly to the music being played (no microphone needed by default).
-   **Microphone Fallback (Android)**: Option to drive the visualizer via microphone input (classic mode).
-   **Customizable**:
    -   **Bars**: 8, 12, or 24 bars.
    -   **Styles**: Segmented 80s, Solid, Glow.
    -   **Colors**: Classic, Cyan, Purple, Mono.
    -   **Tuning**: Adjustable decay speed and noise gate.

### 🎨 Skins & UI
-   **Four Distinct Skins**:
    -   **Spectrum**: Clean, modern visualizer focus.
    -   **Polo**: Skeuomorphic retro car dashboard with LCD font.
    -   **Dot**: Minimalist, fluctuating dot interface with an optional song-info overlay (toggle in settings).
    -   **Void**: Text-driven minimalist home with an integrated sliding library browser and full-name recursive search.
-   **Unified Chrome**: All skins are pluggable "heroes" hosted by a single shell (`VoidScreen`); skin switching no longer changes the navigation surface. Each hero declares whether it hosts the chrome transport row (Spectrum / Dot / Void) or is bespoke (Polo).
-   **Theming**: Dark / light / auto theme variant, light/dark palettes under `lib/theme/palettes/`.
-   **Configurable Transport**: Prev/play/next row position (top/bottom/off) plus horizontal swipe gestures (distance OR velocity threshold) on the hero.
-   **UI Scaling**: "Smart Scale" automatically adjusts button sizes and text for automotive head units and high-DPI displays.
-   **Full Screen Mode**: Settings-driven immersive mode hiding system bars.
-   **Universal Press Feedback**: Every tappable surface — rows, buttons, glyphs, toggles — responds to touch-down with a perceptible opacity dip (calibrated for real-device visibility, 120 ms in / 200 ms out).
-   **Browser Presentation**: Two modes — *fixed* (always visible alongside the hero) or *swipe-up* (hidden until pulled up). In swipe-up mode the open browser sports a drag handle and dismisses on a downward drag of the header band (back button still works).
-   **Tail-Preserving Text**: Long folder paths and track titles head-truncate (`…/Music/Russian Rock`, `…ечный ангел`) so the meaningful end stays on-screen at any UI scale; RTL-aware.
-   **At-a-Glance Settings Status**: Settings sheet opens with a pinned strip showing queue size and a live shuffle toggle above the rest of the groups.

## Skins

### Spectrum
<img width="1277" height="745" alt="image" src="https://github.com/user-attachments/assets/4d2c5d21-d509-492c-ad1f-dfe3ba59c980" />

### Polo
<img width="1277" height="745" alt="image" src="https://github.com/user-attachments/assets/af75f2ed-4e70-487b-9f53-1f313363bc6e" />

### Dot
<img width="1125" height="617" alt="image" src="https://github.com/user-attachments/assets/21ae7465-e6da-4a0e-99af-a41119da2644" />

## Architecture Overview

Nothingness uses a unified provider architecture:

-   **Flutter Layer**: Handles UI, Navigation, Settings, and Visualization rendering.
-   **Audio Backend**: **SoLoud** (`flutter_soloud`) on both macOS and Android — low-latency playback and FFT for the spectrum. Uses a local fork (git submodule at `./soloud`) that adds native Opus decoding to `loadFile`/`loadMem`; clone with `--recurse-submodules` (or run `git submodule update --init`).
-   **Android session/notification**: `audio_service` (`NothingAudioHandler`) owns the MediaSession, lock-screen controls, and background playback, and delegates playback decisions to `PlaybackController`.
-   **Audio focus / interruptions**: `audio_session` subscriptions in `PlaybackController` pause on phone calls / focus loss and resume on focus regain; "becoming noisy" (headphones/BT unplugged) is treated as an explicit pause.
-   **Native fallback**: On Android, an optional `AudioCaptureService` can use the microphone/system mix as a spectrum source if selected in settings.

See [docs/architecture/overview.md](docs/architecture/overview.md) for a deep dive.

## Permissions

-   **Android** (minimum **Android 10 / API 29**):
    -   `READ_MEDIA_AUDIO` (API 33+) / `READ_EXTERNAL_STORAGE` (API 29–32): Required to access and play local music files. The first-launch gate requests only the audio permission — denying microphone or notifications does **not** block library access.
    -   `RECORD_AUDIO`: Required only if using the "Microphone" spectrum source (background mode); requested behind an explicit button in settings.
    -   `POST_NOTIFICATIONS`: Requested silently on API 33+ for playback controls in the notification shade.
-   **macOS**:
    -   File access permissions may be requested by the OS when selecting folders.

## Running the App

1.  Ensure you have Flutter installed.
2.  Run:
    ```bash
    flutter pub get
    flutter run
    ```
3.  **Android**: Select an emulator or device.
4.  **macOS**: Run as a desktop app.

## CI/CD

Automated pipelines via GitHub Actions. See [docs/cicd.md](docs/cicd.md).

## Initial Built With

Cursor Agents (Plan Mode) + Gemini 3 Pro / GPT 5.1 / Opus 4.5 + Flutter.
