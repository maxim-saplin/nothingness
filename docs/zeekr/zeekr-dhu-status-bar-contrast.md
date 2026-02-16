# Zeekr DHU non-immersive status bar contrast note

## Scope

- Platform: Zeekr DHU (Zeekr OS 6.7)
- App mode: non-immersive (`SystemUiMode.edgeToEdge`)
- Date: 2026-02-13

## Symptom

When immersive mode is disabled, the status bar area can become unreadable (black icons/text on dark background).

## Why this happens

In edge-to-edge mode, app content is drawn under a transparent status bar. On this OEM, `statusBarIconBrightness` is ignored -- the platform always renders dark icons. Combined with the app's dark background, this produces black-on-black.

A Flutter-level scrim widget was attempted first but proved unreliable: `MediaQuery.padding.top` can be zero or mis-scaled inside the app's `ScaledLayout` transform on automotive displays.

### Display characteristics

The Zeekr DHU reports `2560x1600 @ 160dpi` (DPR 1.0, logical width 2560). This is wider than typical 1920-pixel IVI displays, so the automotive detection heuristic must cover the full low-DPI + wide-screen range (>= 1600 logical, DPR < 2.0) without an upper width bound.

## App-side mitigation implemented

The fix operates entirely at the platform `SystemUiOverlayStyle` level, which the OEM does respect:

1. **Automotive displays** (detected via low-DPI + wide-screen heuristic):
   - `statusBarColor` is set to an **opaque** scrim color at the platform level
   - Light mode: `0xFFE8E8E8` (light gray) -- dark OEM icons are readable
   - Dark mode: `0xFF2C2C2C` (dark gray) -- in case OEM switches to light icons
2. **Normal phones/tablets**:
   - `statusBarColor` stays **transparent** (standard edge-to-edge)
   - `statusBarIconBrightness` follows system light/dark mode
3. **Brightness tracking**:
   - `didChangePlatformBrightness()` re-applies the style when the system theme changes

## Files changed

- `lib/services/settings_service.dart`
  - Automotive display detection from raw platform view dimensions
  - `_edgeToEdgeOverlayStyleFor()` sets opaque `statusBarColor` on automotive, transparent on phones
  - Brightness-aware icon style for both paths
- `lib/screens/media_controller_page.dart`
  - `didChangePlatformBrightness()` re-applies system UI style on theme change
- `test/services/settings_service_test.dart`
  - Tests for all four combinations: phone/automotive x light/dark mode

## Why this approach

- Operates at the platform `SystemUiOverlayStyle` level, not fragile Flutter widget overlays
- No visual impact on normal phones (transparent status bar, proper icon brightness)
- Automotive detection reuses the existing DPR + width heuristic from UI scaling
- Adapts to light/dark mode changes automatically

## Verification

1. Toggle immersive mode off on DHU -- status bar icons should be readable
2. Switch system theme (light/dark) on DHU -- bar color should adapt
3. On a normal phone -- status bar should remain transparent with correct icon colors
