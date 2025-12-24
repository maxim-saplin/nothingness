# System Architecture Overview

Nothingness is a Flutter-based media visualizer application that now ships with its own cross-platform audio player (Android + macOS). It bridges a modern Flutter UI with both a built-in playback stack and native Android audio capture capabilities when microphone mode is selected.

## High-Level Diagram

```mermaid
graph TD
    User[User / Touch] --> |Interacts| UI[Flutter UI]
    UI --> |Reads/Writes| Settings[SettingsService]
    UI --> |Displays| Vis[SpectrumVisualizer]
    UI --> |Uses| Provider[AudioPlayerProvider (ChangeNotifier)]
    Provider --> |Controls| Player[AudioPlayerService]
    UI --> |Controls| PC[PlatformChannels]
    
    Settings --> |Persists| SP[SharedPreferences]
    
    PC <--> |MethodChannel| Native[Android Native Layer]
    Player --> |PCM Capture| Vis
    Native --> |Audio Data| PC
    Vis <--> |Audio Data Stream| PC
```

## Key Components

### 1. Flutter UI Layer
-   **`MediaControllerPage`**: The main entry point and orchestrator. It manages the layout, including the main visualizer area and the slide-out settings panel. It switches between different screens:
    -   **`SpectrumScreen`**: Standard bar visualizer.
    -   **`PoloScreen`**: Retro LCD-style display.
    -   **`DotScreen`**: Minimalist fluctuating dot interface.
-   **`ScaledLayout`**: A wrapper widget that ensures the entire UI is scaled consistently across different screen DPIs. It now wraps the entire `MediaControllerPage` content (including the Settings overlay) to ensure consistent scaling for all elements (see [UI Scaling](ui-scaling.md)).
    -   **Library Panel**: A swipe-up/arrow-triggered panel with tabs for Now Playing (queue controls) and Folders (folder picker, Play All with recursive enqueue).

### 2. Service Layer
-   **`SettingsService`**: A singleton service responsible for managing application state.
    -   **Spectrum Settings**: Visualizer configuration (colors, bar count, decay speed).
    -   **Audio Source**: Global switch between the built-in player (default) and microphone-based capture.
    -   **UI Scale**: System-wide scaling factor.
    -   **Screen Configuration**: Manages active screen/skin selection (see [Skins & Screens](skins.md)).
    -   **Full Screen Mode**: Immersive sticky mode that hides system status/navigation bars via `SystemChrome`.
    -   **Persistence**: Saves/loads state to disk using `SharedPreferences`.
-   **`AudioPlayerProvider`**: `ChangeNotifier` that mirrors `AudioPlayerService` state (`songInfo`, `isPlaying`, `queue`, `shuffle`, spectrum stream) for the UI. It wires service `ValueNotifier`s into Provider without prop drilling.
-   **`AudioPlayerService`**: Cross-platform playback, queue management, recursive folder scanning, and PCM capture for spectrum data when the audio source is set to player mode.
-   **`PlatformChannels`**: Handles communication with the host Android system.
    -   **Methods**: Controlling media playback (play, pause, next, prev).
    -   **Events**: Receiving real-time audio spectrum data when microphone mode is selected on Android.

### 3. Native Layer (Android)
-   **`AudioCaptureService`**: A native Android service that hooks into the system audio output to capture frequency data.
-   **Method Channels**: Standard Flutter mechanism for passing messages between Dart and Kotlin/Java.

## Data Flow
1.  **Startup**: `NothingApp` pre-initializes and awaits `AudioPlayerProvider.init()` (which initializes SoLoud and playlists) before `runApp`, preventing `SoLoudNotInitializedException`. `SettingsService` loads preferences. `PlatformChannels` initializes the native bridge for Android-specific permissions and microphone capture.
2.  **Runtime (Player mode - default)**: UI reads state from `AudioPlayerProvider`; provider relays `ValueNotifier` updates from `AudioPlayerService` (song info, playing, queue). `AudioPlayerService` streams PCM from playback -> FFT -> provider spectrum stream -> `SpectrumVisualizer` renders frame.
3.  **Runtime (Microphone mode)**: Native layer captures audio -> sends FFT data to Dart via EventChannel -> `SpectrumVisualizer` renders frame. Provider capture is disabled to avoid redundant polling.
4.  **User Action**: User changes settings -> `SettingsService` updates notifier -> UI rebuilds. Spectrum source is switched instantly between player PCM and microphone stream. Permissions (mic/notifications) are surfaced in the Settings screen (Android-only).

## Audio

-   **Audio playback (SoLoud-based)**: The app uses the `flutter_soloud` singleton for cross-platform playback (Android + macOS). `AudioPlayerService` initializes SoLoud once at startup (awaited in `main`), enables visualization, manages queue/seek, and disposes sources before loading the next track to avoid handle leaks. Playback is wrapped in `runZonedGuarded` with skip-on-error and user cancel handling (pause stops the skip loop) to avoid debugger breaks from native callbacks.
-   **Spectrum visualization abstraction**: Spectrum capture is routed through a `SpectrumProvider` interface. `SoLoudSpectrumProvider` polls SoLoud `AudioData` (linear samples) for FFT bars, applying noise-gate and decay smoothing from `SpectrumSettings`. `MicrophoneSpectrumProvider` is Android-only and streams FFT data from the native service via platform channels. macOS uses the player pipeline only (no microphone capture). Settings flips between providers without restarting the UI.

