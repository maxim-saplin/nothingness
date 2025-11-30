# System Architecture Overview

Nothingness is a Flutter-based media visualizer application primarily designed for automotive Android infotainment systems. It bridges a modern Flutter UI with native Android audio capture capabilities.

## High-Level Diagram

```mermaid
graph TD
    User[User / Touch] --> |Interacts| UI[Flutter UI]
    UI --> |Reads/Writes| Settings[SettingsService]
    UI --> |Displays| Vis[SpectrumVisualizer]
    UI --> |Controls| PC[PlatformChannels]
    
    Settings --> |Persists| SP[SharedPreferences]
    
    PC <--> |MethodChannel| Native[Android Native Layer]
    Native --> |Audio Data| PC
    Vis <-- |Audio Data Stream| PC
```

## Key Components

### 1. Flutter UI Layer
-   **`MediaControllerPage`**: The main entry point and orchestrator. It manages the layout, including the main visualizer area and the slide-out settings panel.
-   **`ScaledLayout`**: A wrapper widget that ensures the entire UI is scaled consistently across different screen DPIs (see [UI Scaling](ui-scaling.md)).

### 2. Service Layer
-   **`SettingsService`**: A singleton service responsible for managing application state.
    -   **Spectrum Settings**: Visualizer configuration (colors, bar count, decay speed).
    -   **UI Scale**: System-wide scaling factor.
    -   **Screen Configuration**: Manages active screen/skin selection (see [Skins & Screens](skins.md)).
    -   **Persistence**: Saves/loads state to disk using `SharedPreferences`.
-   **`PlatformChannels`**: Handles communication with the host Android system.
    -   **Methods**: Controlling media playback (play, pause, next, prev).
    -   **Events**: Receiving real-time audio spectrum data.

### 3. Native Layer (Android)
-   **`AudioCaptureService`**: A native Android service that hooks into the system audio output to capture frequency data.
-   **Method Channels**: Standard Flutter mechanism for passing messages between Dart and Kotlin/Java.

## Data Flow
1.  **Startup**: `SettingsService` loads preferences. `PlatformChannels` initializes connection to native side.
2.  **Runtime**: Native layer captures audio -> sends FFT data to Dart via EventChannel -> `PlatformChannels` broadcasts stream -> `SpectrumVisualizer` renders frame.
3.  **User Action**: User changes settings -> `SettingsService` updates notifier -> UI rebuilds -> `PlatformChannels` pushes update to native side (if needed).

