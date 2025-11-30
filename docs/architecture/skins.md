# Skins & Screen System

Nothingness supports multiple screen types, allowing for radically different visual presentations. The system is designed to distinguish between **Screens** (functional layouts) and **Skins** (aesthetic variations of a layout, primarily the "Polo" style).

## Screen Concepts

The application uses `ScreenConfig` models to define which screen is currently active.

-   **Spectrum Screen**: The default, modern visualization with dynamic bars and a clean UI.
-   **Polo Screen**: A skeuomorphic design mimicking a car head unit, using a static background image and a retro LCD font.

## The Polo Skin

The "Polo" screen is an example of a coordinate-based skin. It consists of:

1.  **Background Image**: A high-resolution image of a car dashboard or radio (`assets/images/polo.png`).
2.  **LCD Content**: A widget (`RetroLcdDisplay`) rendering text with the `Press Start 2P` pixelated font.
3.  **Coordinate System**: The content is positioned using a normalized `Rect` (0.0 to 1.0) relative to the background image.

### Aspect Ratio Handling

The `SkinLayout` widget ensures that the LCD content remains perfectly aligned with the background image, regardless of the screen's aspect ratio or resolution.

-   The background image uses `BoxFit.contain`.
-   The widget calculates the *actual* rendered rectangle of the image on the screen.
-   The LCD coordinates are applied relative to this rendered rectangle, not the full screen bounds.

### Coordinate System

Coordinates are defined in `lib/models/screen_config.dart`. They are **normalized percentages**:

-   `left`: 0.0 is the left edge of the image, 1.0 is the right edge.
-   `top`: 0.0 is the top edge, 1.0 is the bottom edge.

Example:
```dart
// Starts at 31% width, 38% height
// Width is 37% of image width, Height is 14% of image height
this.lcdRect = const Rect.fromLTWH(0.31, 0.38, 0.37, 0.14),
```

### Debug Mode (macOS Only)

To facilitate finding the correct coordinates for new skins:

1.  Run the app on **macOS**.
2.  Open **Settings** -> Select **Polo**.
3.  Toggle **Debug Layout** to **On**.
4.  A red box will appear showing the current `lcdRect` and its coordinates.
5.  Adjust the values in `lib/models/screen_config.dart` and use **Hot Reload** to see changes instantly.

*Note: The `lcdRect` configuration is intentionally NOT persisted to disk. The code is the single source of truth, allowing for easy tweaking during development.*

