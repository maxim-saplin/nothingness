# Nothingness – Retro Audio Player & Spectrum Visualizer

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/maxim-saplin/nothingness)](https://github.com/maxim-saplin/nothingness/releases/latest)

Nothingness is a **fully-fledged audio player** and **retro spectrum visualizer** for Android and macOS. It plays your local music library while rendering a pixelated, 80s‑style spectrum analyzer driven directly by the audio playback.

Originally inspired by a need for digital minimalism in modern cars (specifically the Zeekr infotainment system), it features a **Global UI Scaling** engine that adapts the interface to any screen DPI, making it perfect for car dashboards, tablets, and desktops.

<img width="1125" height="617" alt="image" src="https://github.com/user-attachments/assets/21ae7465-e6da-4a0e-99af-a41119da2644" />

## Features

### 🎵 Audio Player
-   **Local Playback**: Plays audio files from your device's storage.
-   **Library Management**:
    -   **Folder Picker**: Select folders to play.
    -   **Recursive Enqueue**: "Play All" adds all tracks in a folder and its subfolders.
    -   **Queue Control**: Reorder, remove, and manage your Now Playing queue.
-   **Platform Integration**:
    -   **Android**: Full media session support, background playback, lock screen controls, and notification controls.
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
-   **Three Distinct Skins**:
    -   **Spectrum**: Clean, modern visualizer focus.
    -   **Polo**: Skeuomorphic retro car dashboard with LCD font.
    -   **Dot**: Minimalist, fluctuating dot interface.
-   **UI Scaling**: "Smart Scale" automatically adjusts button sizes and text for automotive head units and high-DPI displays.
-   **Full Screen Mode**: Immersive mode hiding system bars.

## Skins

### Spectrum
<img width="1277" height="745" alt="image" src="https://github.com/user-attachments/assets/4d2c5d21-d509-492c-ad1f-dfe3ba59c980" />

### Polo
<img width="1277" height="745" alt="image" src="https://github.com/user-attachments/assets/af75f2ed-4e70-487b-9f53-1f313363bc6e" />

### Dot
<img width="1277" height="745" alt="image" src="https://github.com/user-attachments/assets/acc57317-2d98-4503-bf69-6ed783f49f8b" />

## Architecture Overview

Nothingness uses a unified provider architecture with platform-specific backends:

-   **Flutter Layer**: Handles UI, Navigation, Settings, and Visualization rendering.
-   **Audio Backend**:
    -   **macOS**: Uses **SoLoud** (`flutter_soloud`) for low-latency playback and FFT data.
    -   **Android**: Uses **Just Audio** + **Audio Service** for robust background playback and media session management. Spectrum data is pulled from the Android Visualizer API tied to the player session.
-   **Native Fallback**: On Android, an optional `AudioCaptureService` can still use the microphone/system mix if selected in settings.

See [docs/architecture/overview.md](docs/architecture/overview.md) for a deep dive.

## Permissions

-   **Android**:
    -   `READ_MEDIA_AUDIO` / `READ_EXTERNAL_STORAGE`: Required to access and play local music files.
    -   `RECORD_AUDIO`: Required only if using the "Microphone" spectrum source.
    -   `POST_NOTIFICATIONS`: For playback controls in the notification shade.
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

## Built With

Cursor Agents (Plan Mode) + Gemini 3 Pro / GPT 5.1 / Opus 4.5 + Flutter.
