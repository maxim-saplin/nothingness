## Nothingness – Media Controller with 80s Spectrum Visualizer

Nothingness is a Flutter app that shows the **currently playing track on Android**
and renders a retro, 80s‑style **pixelated spectrum analyzer** driven by the
microphone.

Inspired by a 1 week de-toxing from Zeekr infrotainment while driving VW Polo - I releized I want a simple screen instead of youtube or map just to feel the ever eluding "nothingness" -> see https://www.youtube.com/watch?v=orQKfIXMiA8

Oh, btw, it auto adjusts to Zeekrэs notorious DPI (that's when standard Android apps show very small text and buttons).

<img width="1378" height="815" alt="image" src="https://github.com/user-attachments/assets/f7519a5b-0a8e-48bf-9fac-fce18bcfffad" />

### Features

- **Now Playing**
  - Reads metadata (title/artist/album) from active media sessions on Android.
  - Simple media controls: **Previous / Play‑Pause / Next**.

- **Spectrum Visualizer**
  - Microphone‑based FFT analyzer with 8 / 12 / 24 bars.
  - Pixelated, segmented bars reminiscent of old audio decks.
  - Tunable:
    - Noise gate sensitivity (how quiet is considered “silence”).
    - Bar count.
    - Color scheme (Classic / Cyan / Purple / Mono).
    - Bar style (Segmented 80s / Solid / Glow).
    - Decay speed.

- **Settings**
  - Three‑dot button in the top‑right toggles the **slide-in Settings Panel**.
  - The panel overlays the right side of the screen with a frosted glass effect, allowing live preview of changes.
  - Settings are persisted locally and pushed down to native Kotlin code.

### Architecture Overview

- **Flutter (Dart)**
  - UI, navigation, settings, persistence, visualization.
  - Custom painter for the spectrum and labels.
  - `MethodChannel` + `EventChannel` wrappers in `lib/services/platform_channels.dart`.
  - `SettingsService` in `lib/services/settings_service.dart` acts as the single source of truth for defaults and persistence.

- **Android (Kotlin)**
  - `MediaSessionService` (NotificationListenerService) reads active sessions and
    controls playback.
  - `AudioCaptureService` uses `AudioRecord` + in‑house FFT to compute spectrum
    magnitudes and stream bar values to Flutter.
  - `MainActivity` wires up platform channels and forwards spectrum settings
    (noise gate, bar count, decay speed) from Flutter to `AudioCaptureService`.

### Permissions & Requirements

- **Android**
  - Minimum recommended: Android 12 / 12L or later.
  - Permissions:
    - `RECORD_AUDIO` – required for microphone‑based spectrum.
    - Notification access – required to read media metadata and control playback.
  - The app will:
    - Ask for microphone permission.
    - Offer a button to open notification‑access settings.

- **macOS**
  - Used mainly for UI debugging.
  - Shows a “macOS Preview” message and does **not** perform media or spectrum
    operations.

### Running the App

1. Ensure you have Flutter installed and on your `PATH`.
2. From the project root:

   ```bash
   flutter pub get
   flutter run
   ```

3. Select an **Android device or emulator** for full functionality.

### Tuning the Spectrum

- Start with:
  - Bars: **12** or **24**
  - Noise gate: around **‑40 dB**
  - Decay: **Medium**
- In a **silent room**, bars should be mostly flat.
- With a **loud song or speaking near the mic**, bars should reach near the top,
  mainly on low and mid frequencies.

If you change the visual style (bar count, colors, etc.) in **Settings**, the
media control buttons and other accents automatically sync to that scheme.

## Built With

Cursor Agents (actively used Plan Mode) + Gemini 3 Pro/GPT 5.1 High/ Opus 4.5 High (it's facinating how one model acan get into loop trying to fix smth and then another models chimes in, can't say that one model is definetly better than the other, it's speed of responses that mattered AND whichever model stick in the model picker after the recent bug loop and model switching) + Flutter - over one evening and morning on Nov 29 and 30, 2025.
