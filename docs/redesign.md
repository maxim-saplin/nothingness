# Nothingness: To-Be Architecture & Re-Architecture Plan

**Status**: Deep-dive analysis (2026-05-30)  
**Current lib/ LOC**: 11,878 across 61 files  
**Target lib/ LOC**: < 6,200  
**Target reduction**: ~48% without feature loss  

---

## 1. GOLDEN REQUIREMENTS SET

All user-facing features and behaviors the re-architecture MUST preserve, organized by functional area.

### Playback & Transport

1. **Load & Play Local Audio**
   - Load individual tracks and folders (recursive "Play All")
   - Display current song info (title, artist, duration, elapsed position)
   - Support standard transport: play, pause, next, previous, seek
   - Skip to any track in queue

2. **Queue Management**
   - Enqueue tracks and folders (including recursive subfolders)
   - Reorder queue items via UI
   - Remove individual tracks from queue
   - Shuffle (on/off) with deterministic re-queue behavior
   - One-shot playback (play a track outside the queue; return to queued position on end)

3. **Audio Error Recovery**
   - Skip unplayable/missing files automatically
   - Track isNotFound flag to avoid infinite loops
   - Transient error streak guard (max 3 errors in 30s window)
   - Respect user intent when errors occur (don't auto-play if user paused)

4. **Platform Integration (Android)**
   - MediaSession with lock-screen controls
   - System notification with transport buttons
   - Background playback with cached audio-session
   - Sub-150 ms transport response in common case

5. **Audio Focus & Route Handling (Android)**
   - Pause on phone call / navigation prompt; auto-resume on focus regain
   - Permanent focus loss (e.g., navigating away) does not auto-resume
   - Pause on "becoming noisy" (headphones/BT unplugged); no auto-resume
   - Log audio-event timestamps for diagnostics

### Library & Search

6. **Folder Navigation**
   - Browse file system (local storage on Android, arbitrary paths on macOS)
   - Last-folder restore across app sessions
   - Breadcrumb navigation (tap to jump to parent)
   - "Jump to Now-Playing" glyph: teleport browser to playing track's folder, center the row

7. **Global Search**
   - Type-ahead search across entire library (full-name recursive match)
   - Tapping a result installs result list as temporary sub-queue
   - Restore original queue when dismissing search
   - Search focus / unfocus triggers browser state transitions

8. **Android MediaStore Integration**
   - Auto-refresh on app focus (MediaStore change detection)
   - Folder repair: auto-fix Android 11+ scoped-storage paths
   - Smart folder labels (e.g., "Music" instead of `/storage/emulated/0/Music`)
   - Permission gating: deny audio permission → no library access

9. **Metadata**
   - Extract title/artist from file metadata (ID3, Vorbis, etc.)
   - Fallback to filename when metadata absent or when setting enabled
   - Cached metadata to avoid re-parsing

### Spectrum Visualizer

10. **Visualizer Rendering**
    - Display 8, 12, or 24 bars
    - Three bar styles: Segmented (80s), Solid, Glow
    - Four color schemes: Classic, Cyan, Purple, Monochrome
    - Configurable decay speed (Slow, Medium, Fast)
    - Adjustable noise gate (dB threshold)
    - Real-time frequency-bin rendering

11. **Audio Source Selection (Android)**
    - Default: SoLoud playback-driven FFT
    - Optional: Microphone fallback (RECORD_AUDIO permission)
    - Switchable at runtime without restart

### Skins & UI Layout

12. **Four Distinct Skins**
    - **Spectrum**: Visualizer-focused, media controls overlay
    - **Polo**: Skeuomorphic car LCD with retro font (bespoke transport)
    - **Dot**: Minimalist fluctuating dot with optional song-info overlay
    - **Void**: Text-driven minimalist home with integrated sliding library

13. **Unified Shell Architecture**
    - Single `VoidScreen` hosts all four heroes as pluggable visuals
    - Skin switching does not change navigation surface
    - Each hero declares: hostsChromeTransport (yes/no), usesVisualizer (yes/no)
    - Polo owns its own transport row; others use shared chrome transport

14. **Browser Presentation**
    - **Fixed**: Always visible alongside hero
    - **Swipe-up**: Hidden until pulled; drag handle to dismiss; back button still works

15. **Transport Row**
    - Configurable position: top / bottom / off
    - Horizontal swipe gestures: distance OR velocity threshold for prev/next
    - Responsive to touch-down with opacity dip (120 ms in, 200 ms out)

### Theming & Display

16. **Theme System**
    - Dark / Light / Auto theme variant
    - Per-theme palettes (currently Void Dark / Void Light)
    - Real-time theme switching in settings
    - Unified palette/typography/geometry abstraction

17. **UI Scaling**
    - "Smart Scale" auto-detects automotive (low-DPI, wide: <2.0 dpi, >=1600 logical width) vs. mobile/tablet
    - Button/text scaling: 1.0..3.0 range, responsive to screen DPI
    - Consistent scaling across entire app (via `ScaledLayout` wrapper)
    - Manual override in settings

18. **Full-Screen Mode**
    - Immersive mode: hides system bars
    - Sticky per-session
    - Responsive to settings toggle

19. **Text Rendering**
    - Tail-preserving text: long paths/titles head-truncate so meaningful end stays visible
    - RTL-aware text layout

### Settings

20. **Settings Storage & Migration**
    - Persist all settings to SharedPreferences
    - One-shot migrations (e.g., legacy single-blob screen config → per-screen keys)
    - Per-screen config persistence (active screen ID + per-ID blobs)
    - EQ settings (currently no-op but structure preserved)

21. **Settings UI Sheet**
    - Pinned status strip: queue size + shuffle toggle (when non-empty)
    - Grouped sections: MODE / LOOK / SOUND / LIBRARY / EXTERNAL / DISPLAY / ABOUT
    - Row primitives: cycle (enum), slider (double), toggle (bool), info
    - Adaptive: show/hide rows based on operating mode and active skin
    - Permission checks: show request buttons (audio, mic, notifications)

22. **Operating Modes**
    - Enumeration: Own / DelegatedPause / DelegatedFocus
    - Exposed in settings, affects which visualizer-focus mode is active

### Diagnostics & Debugging

23. **Diagnostics Snapshot Export**
    - Audio events ring buffer (300-entry log of audio session changes)
    - Last-error attribution (path, reason, message, timestamp)
    - Playback controller state snapshot
    - VM service extension triggers

24. **Logging Service**
    - Capture playback controller logs (when enabled)
    - Recent-logs ring buffer (capacity configurable)
    - Log screen UI for real-time/exported diagnostics

25. **Debug Hooks**
    - VM service callbacks for agent-driven testing
    - Immersive state lookup
    - Library controller + navigator key exposure
    - Boot stopwatch (main → first frame timing)

### Platform & Session

26. **Android Specific**
    - Minimum API 29 (Android 10)
    - Audio permission: READ_MEDIA_AUDIO (API 33+) / READ_EXTERNAL_STORAGE (API 29–32)
    - Microphone permission: RECORD_AUDIO (optional, behind explicit button)
    - Notification permission: POST_NOTIFICATIONS (API 33+, silent)
    - ARM64 only (no armeabi-v7a / x86_64)

27. **macOS Specific**
    - Native playback via SoLoud
    - File access permissions (OS-gated on folder selection)
    - Desktop app launcher

28. **Bootstrap Performance**
    - Synchronous `runApp` → immediate splash frame (black ColoredBox)
    - Heavy init in microtask: Hive, LibraryService, AudioService, AudioPlayerProvider
    - Target: ~300 ms first frame (debug emulator)

---

## 2. AS-IS ARCHITECTURE

### File Inventory & Dependency Map

#### Services (4,081 LOC, 16 files)

| File | LOC | Responsibility | Key Types | Dependents |
|------|-----|-----------------|-----------|-----------|
| `playback_controller.dart` | 1096 | Playback logic, queue, error recovery, audio focus handling | PlaybackController, PlayIntent, _SearchSession | AudioPlayerProvider, NothingAudioHandler, tests |
| `settings_service.dart` | 542 | App state persistence, notifier management | SettingsService, ~15 ValueNotifiers | VoidScreen, VoidSettingsSheet, VoidBrowser, main, 8+ importers |
| `soloud_transport.dart` | 389 | SoLoud native wrapper, FFT, playback control | SoLoudTransport | AudioPlayerProvider, PlaybackController |
| `android_smart_roots.dart` | 352 | Android storage root discovery + friendly labels | AndroidSmartRoots, StorageRoot | VoidBrowser (1 importer) |
| `playlist_store.dart` | 309 | Queue persistence via Hive | PlaylistStore, _PlaylistSnapshot | PlaybackController, tests |
| `nothing_audio_handler.dart` | 299 | Android MediaSession + notification state | NothingAudioHandler | main, AudioPlayerProvider |
| `platform_channels.dart` | 199 | Android MethodChannel / EventChannel bridges | PlatformChannels | SettingsService, PlaybackController, LibraryController, metadata_extractor |
| `metadata_extractor.dart` | 176 | ID3 / Vorbis parsing | MetadataExtractor | LibraryBrowser, tests |
| `library_browser.dart` | 142 | Folder traversal + file discovery | LibraryBrowser | VoidBrowser, VoidScreen, tests |
| `library_service.dart` | 116 | Folder permissions (restore per Android 11+) | LibraryService | main, VoidScreen |
| `soloud_spectrum_provider.dart` | 109 | FFT bin → spectrum bar data | SoLoudSpectrumProvider | SpectrumVisualizer, tests |
| `spectrum_analyzer.dart` | 83 | Frequency-bin decay + smoothing | SpectrumAnalyzer | tests only |
| `media_store_freshness.dart` | 82 | MediaStore change detection (Android) | MediaStoreFreshness | LibraryController (indirect via logging) |
| `audio_transport.dart` | 80 | Thin playback abstraction (interface) | AudioTransport, TransportEvent | PlaybackController, SoLoudTransport, NothingAudioHandler |
| `automation_intent_service.dart` | 67 | Android intent listener (Tasker / MacroDroid) | AutomationIntentService | main |
| `logging_service.dart` | 40 | Ring-buffer logging | LoggingService | VoidBrowser, LibraryController |

**Accidental Complexity**: 
- `SettingsService` exposes **15 separate ValueNotifiers** (each setting = 1 notifier + getters + setters + load/save). This is the **largest boilerplate source** (~40% of its 542 LOC).
- Settings loading/saving is interspersed with defaults and migration logic across the entire file.
- Per-screen config requires polymorphic JSON encoding/decoding across 4 ScreenConfig subclasses — 287 LOC in `screen_config.dart` alone.

#### Providers (434 LOC, 1 file)

| File | LOC | Responsibility | Key Types | Dependents |
|------|-----|-----------------|-----------|-----------|
| `audio_player_provider.dart` | 434 | ChangeNotifier wrapper over PlaybackController | AudioPlayerProvider | VoidScreen, VoidSettingsSheet, VoidBrowser, TransportRow, all hero widgets, main |

**Accidental Complexity**: 
- Mirrors PlaybackController state reactively (8 getters + 2 stream subscriptions) for 434 LOC.
- Android-specific mirroring of NothingAudioHandler streams adds boilerplate.

#### Controllers (591 LOC, 1 file)

| File | LOC | Responsibility | Key Types | Dependents |
|------|-----|-----------------|-----------|-----------|
| `library_controller.dart` | 591 | Folder state, search, track discovery, permissions | LibraryController, SearchState | VoidBrowser, VoidScreen, tests |

**Accidental Complexity**: 
- Mixes three concerns: folder navigation, search logic, Android permissions + MediaStore refresh.
- 17 imports suggest high coupling.

#### Widgets (3,885 LOC, 19 files)

| File | LOC | Responsibility | Key Types | Dependents |
|------|-----|-----------------|-----------|-----------|
| `void_browser.dart` | 837 | Library folder listing + search UI | VoidBrowser | VoidScreen |
| `void_settings_sheet.dart` | 786 | Settings UI: MODE / LOOK / SOUND / LIBRARY / DISPLAY / ABOUT groups | VoidSettingsSheet, row builders (_row, _sliderRow, _toggleRow) | VoidScreen |
| `spectrum_visualizer.dart` | 376 | FFT bars rendering | SpectrumVisualizer | all hero widgets |
| `hero_feedback_surface.dart` | 355 | Hero tap zone + swipe gesture detection | HeroFeedbackSurface | VoidScreen |
| `skin_layout.dart` | 228 | Polo-specific layout (LCD + buttons) | SkinLayout | PoloHero |
| `transport_row.dart` | 189 | Prev / Play / Next buttons + icons | TransportRow | VoidScreen |
| `void_hero.dart` | 141 | Void skin (text-driven, no visualizer) | VoidHero | VoidScreen |
| `retro_ticker.dart` | 132 | Animated time display | RetroTicker | PoloHero, RetroLcdDisplay |
| `retro_lcd_display.dart` | 109 | LCD-style song info card | RetroLcdDisplay | PoloHero |
| `mid_ellipsis.dart` | 109 | Head-truncating text widget | MidEllipsis | VoidBrowser, VoidScreen (and many others) |
| `spectrum_hero.dart` | 89 | Spectrum skin hero | SpectrumHero | VoidScreen |
| `scaled_layout.dart` | 81 | Global UI scaling wrapper | ScaledLayout | main (wraps entire page) |
| `polo_hero.dart` | 81 | Polo skin hero (LCD retro car) | PoloHero | VoidScreen |
| `media_button.dart` | 79 | Icon button with press feedback | MediaButton | SpectrumHero, PoloHero, etc. |
| `dot_hero.dart` | 74 | Dot skin hero (fluctuating dot) | DotHero | VoidScreen |
| `press_feedback.dart` | 68 | Universal touch-down opacity dip | PressFeedback | many widgets |
| `hero_title_block.dart` | 63 | Song info / track title overlay | HeroTitleBlock | SpectrumHero, DotHero |
| `base_hero_container.dart` | 45 | Base styling for all heroes | BaseHeroContainer | all heroes |
| `phone_frame.dart` | 43 | Debug desktop phone frame wrapper | PhoneFrame | main (optional) |

**Accidental Complexity**: 
- `void_browser.dart` (837 LOC) and `void_settings_sheet.dart` (786 LOC) are "god widgets" mixing layout, state reading, and row building.
- `void_settings_sheet.dart` manually constructs **15 settings groups**, each cycling through enums / sliders / toggles with duplicated row builders.
- Hero widgets are shallow (74–141 LOC) but each has identical import footprints (9–10 imports each) with most just theme / palette lookups.
- `PressFeedback` + `HeroFeedbackSurface` duplicate touch feedback logic.

#### Screens (906 LOC, 3 files)

| File | LOC | Responsibility | Key Types | Dependents |
|------|-----|-----------------|-----------|-----------|
| `void_screen.dart` | 907 | Main shell: hero selection, browser visibility, chrome layout | VoidScreen | main |
| `media_controller_page.dart` | 242 | App entry point, SettingsService init, skin selection | MediaControllerPage | main |
| `help_screen.dart` | 170 | Help / info screen (not integrated) | HelpScreen | — |
| `log_screen.dart` | 231 | Diagnostics log viewer | LogScreen | — |

**Accidental Complexity**: 
- `void_screen.dart` (907 LOC) is the "main shell": orchestrates hero, browser, transport row, immersive mode, swipe-up animation, search focus, hint timers, jump-glyph debouncing. Manages 8+ animation controllers and 12+ listener bindings. Each settings notifier triggers a full rebuild.

#### Models (766 LOC, 12 files)

Mostly data classes with boilerplate JSON serialization:
- `screen_config.dart` (287 LOC): polymorphic JSON + 4 copyWith variants for 4 ScreenConfig subclasses
- `spectrum_settings.dart` (118 LOC): enum definitions, JSON codec, copyWith
- `eq_settings.dart` (68 LOC): stub EQ state, JSON codec
- `audio_track.dart`, `song_info.dart`, `supported_extensions.dart`, `audio_track.dart`, etc.: tiny data classes with JSON helpers

**Accidental Complexity**: 
- Each model has toJson / fromJson / copyWith + defaults mirrored in SettingsService.
- SpectrumSettings defaults live in both the model AND SettingsService (fragile single-source-of-truth).

#### Theme (327 LOC, 5 files)

- `themes.dart` (71 LOC): MaterialTheme builder
- `app_palette.dart` (not shown): Color abstractions
- `app_typography.dart` (not shown): Typography abstractions
- `app_geometry.dart` (not shown): Layout abstractions
- `palettes/void_*.dart` (2 files): Void dark/light color defs

**Accidental Complexity**: 
- Three separate abstraction layers (Palette, Typography, Geometry) passed around as instance fields in many widgets rather than via context-based lookup.

#### Main & Debug (264 + 28 LOC)

- `main.dart` (264 LOC): Bootstrap, Hive init, AudioService, heavy init in microtask, provider setup
- `debug_hooks.dart` (28 LOC): Singleton for VM service callbacks

**Accidental Complexity**: 
- Bootstrap orchestrates 5 services in sequence; if any fails, no fallback.

### Dependency Graph Hotspots

```
                    VoidScreen (907 LOC)
                          |
       ____________|_____________
       |           |             |
   VoidBrowser  Transport  HeroFeedback
   (837 LOC)    Row (189)  Surface (355)
       |                         |
   Library       [4 heroes]
   Controller        |
   (591 LOC)     SpectrumViz (376)
       |             |
   Settings --------+
   Service (542)    
   (15 notifiers)
```

**Core Issues**:
1. **Settings-driven rebuilds**: 15 ValueNotifiers in SettingsService → every change touches full widget tree. VoidScreen and VoidSettingsSheet each listen to 12–15 notifiers, rebuilding on any change.
2. **God widgets**: VoidBrowser (837) and VoidSettingsSheet (786) mix layout, state reading, and row building with no extraction.
3. **Shallow modules**: Hero widgets (74–141 LOC) redundantly import theme 3x (palette, typography, geometry) + provider + models.
4. **Per-skin config duplication**: Four ScreenConfig subclasses duplicate JSON / copyWith boilerplate.
5. **Library complexity**: LibraryController (591 LOC) tangles folder navigation, search, permissions, and Android MediaStore refresh.
6. **Provider indirection**: AudioPlayerProvider (434 LOC) mirrors PlaybackController state; adds no logic, only reactive wrapper.

---

## 3. TO-BE ARCHITECTURE

### Redesign Principles

1. **Data-driven settings**: Replace 15 hand-written ValueNotifiers with a single `SettingsRegistry<T>` that auto-generates getters, setters, persistence.
2. **Reduce settings rebuild surface**: Batch setting reads, use `Selector` or local state where full app rebuild is unnecessary.
3. **Collapse god widgets**: Split VoidBrowser (837 → ~350) and VoidSettingsSheet (786 → ~250) into composable row builders and list items.
4. **Merge shallow modules**: Fold 4 ScreenConfig subclasses into a single data-driven "screen config" registry; hero widgets become pure render functions, not full State widgets.
5. **Simplify library**: Partition LibraryController into discrete services: FolderNavigator (folder state), SearchEngine (query + matching), PermissionManager (Android gating).
6. **Eliminate redundant wrappers**: Inline AudioPlayerProvider into PlaybackController state exposure (use a single ChangeNotifier in PlaybackController itself).
7. **Consolidate layout**: Reuse press-feedback primitive across all touch targets; unify theme lookups via a single ThemeContext.

### Proposed Module Structure

#### Core Data (Immutable, ~700 LOC)

- **`models/setting.dart`** (NEW, ~120 LOC): `Setting<T>` base class with key, default, JSON codec, label; `SettingRegistry` to auto-generate persistence + getters.
  - Replaces: manual ValueNotifier in SettingsService, per-setting JSON helpers.
  - Mechanism: `registry.of<BarCount>('barCount')` returns a reactive handle; persist / notify on change auto-handled.

- **`models/screen.dart`** (NEW, ~80 LOC, replaces `screen_config.dart` 287 LOC): `ScreenLayout` enum; single config class (not 4 subclasses) with optional per-skin fields.
  - Mechanism: `screenConfig.visSettings(skin: ScreenType.spectrum).spectrumWidthFactor` → inline getters, no polymorphism.

- **`models/audio_*.dart`** (unchanged, ~200 LOC): AudioTrack, SongInfo, SpectrumSettings, etc.

- **`models/enums.dart`** (NEW, ~100 LOC): Consolidate BarCount, BarStyle, DecaySpeed, SpectrumColorScheme, ThemeId, ThemeVariant, TransportPosition, BrowserPresentation, OperatingMode, ScreenType.
  - Benefit: Single import `enums.dart` for all UI enum cycles.

- **`models/metadata.dart`** (NEW, ~50 LOC): AudioMetadata (title, artist, duration).

- **`models/library.dart`** (NEW, ~70 LOC): FolderNode, SearchQuery, SearchResult.

#### Services (Decoupled, Lean, ~2,000 LOC)

- **`services/settings.dart`** (NEW, ~250 LOC, replaces `settings_service.dart` 542 LOC): SettingsRepository (load/save persistence layer); SettingRegistry (auto-notifier + in-memory cache); immutable SettingsSnapshot read-only view.
  - Mechanism: `registry.watch<bool>('shuffle')` returns reactive Stream; UI subscribes to only needed settings.

- **`services/playback/playlist.dart`** (NEW, ~150 LOC, from `playlist_store.dart` 309 LOC): PlaylistStore unchanged; no LOC savings but clearer module boundary.

- **`services/playback/controller.dart`** (NEW, ~900 LOC, from `playback_controller.dart` 1096 LOC): Inline PlayIntent, _SearchSession, _SelectionReason into type-driven state machine. Extract queue-skip logic into `QueueSkipStrategy` class. Reduce inline diagnostics.
  - Mechanism: `controller.state` → StateNotifier<PlayState>; UI watches `controller.state.asStream()`.

- **`services/playback/transport.dart`** (NEW, ~200 LOC): AudioTransport interface + SoLoudTransport unchanged but moved to module.

- **`services/audio_focus.dart`** (NEW, ~80 LOC): Extract audio-session listening from PlaybackController.

- **`services/library/navigator.dart`** (NEW, ~150 LOC, from `library_controller.dart` 591 LOC): FolderNavigator — load, navigate, breadcrumb.

- **`services/library/search.dart`** (NEW, ~100 LOC, from `library_controller.dart`): SearchEngine — query matching, result ranking.

- **`services/library/browser.dart`** (NEW, ~100 LOC, from `library_browser.dart` 142 LOC): unchanged.

- **`services/library/permissions.dart`** (NEW, ~80 LOC, from `library_controller.dart`): PermissionManager — Android-specific gating.

- **`services/android/smart_roots.dart`** (NEW, ~350 LOC): renamed from `android_smart_roots.dart`.

- **`services/platform_channels.dart`** (~199 LOC): unchanged.

- **`services/metadata.dart`** (~176 LOC): unchanged from `metadata_extractor.dart`.

#### UI State & Composition (~1,600 LOC, heavy reduction from 3,885 in widgets/)

**Providers/State Management** (~200 LOC):
- **`ui/playback_notifier.dart`** (NEW, ~80 LOC, replaces `audio_player_provider.dart` 434 LOC): Single `PlaybackNotifier(PlaybackController)` ChangeNotifier that exposes controller state; **no mirroring**, just field-forwarding getters. Eliminated ~350 LOC of reactive boilerplate.

- **`ui/settings_notifier.dart`** (NEW, ~70 LOC): SettingsNotifier watches SettingRegistry; rebuilds only on subscribed-setting changes (via Selector in widgets).

- **`ui/library_notifier.dart`** (NEW, ~50 LOC): FolderNavigator + SearchEngine as reactive provider.

**Core Widgets** (~650 LOC):
- **`ui/widgets/visualizer.dart`** (~376 LOC): SpectrumVisualizer unchanged.

- **`ui/widgets/browser.dart`** (NEW, ~300 LOC, from `void_browser.dart` 837 LOC): Split into:
  - `BrowserListItem` (pure widget, ~50 LOC): Renders one folder/file.
  - `BrowserSearch` (stateful, ~70 LOC): Search input + result list.
  - `BrowserPane` (stateful, ~180 LOC): Folder listing + breadcrumb + search orchestration.
  - Mechanism: ItemBuilder callback + list projection.

- **`ui/widgets/settings_sheet.dart`** (NEW, ~250 LOC, from `void_settings_sheet.dart` 786 LOC): Split into:
  - `SettingRow` (pure widget, ~40 LOC): Generic cycle / slider / toggle renderer.
  - `SettingSection` (pure widget, ~40 LOC): Group + header.
  - `SettingsPane` (stateful, ~170 LOC): Orchestration + permission checks.
  - Mechanism: SettingRow renders from Setting<T> descriptor; no manual _row / _sliderRow duplicates.

- **`ui/widgets/transport_row.dart`** (~189 LOC): unchanged.

- **`ui/widgets/hero_feedback.dart`** (~355 LOC): unchanged (but may extract touch-feedback primitive).

- **`ui/widgets/press_feedback.dart`** (~68 LOC): unchanged; reused universally.

- **`ui/widgets/theme_context.dart`** (NEW, ~40 LOC): Replace instance-field threading (palette, typography, geometry) with `ThemeContext.of(context)` helper.

**Skins** (~300 LOC):
- **`ui/skins/base.dart`** (NEW, ~50 LOC): HeroBase mixin, `HeroSpec` descriptor.

- **`ui/skins/spectrum.dart`** (NEW, ~80 LOC, from `spectrum_hero.dart` 89): Pure function + HeroSpec config.

- **`ui/skins/polo.dart`** (NEW, ~90 LOC, from `polo_hero.dart` 81 + `skin_layout.dart` 228): Merged; LCD rendering inlined.

- **`ui/skins/dot.dart`** (NEW, ~50 LOC, from `dot_hero.dart` 74): Pure function + HeroSpec.

- **`ui/skins/void.dart`** (NEW, ~30 LOC, from `void_hero.dart` 141): Typography-only hero.

**Screens** (~250 LOC):
- **`screens/home.dart`** (NEW, ~250 LOC, from `void_screen.dart` 907 LOC): Simplified orchestrator:
  - Hero selection via `ScreenType` enum → lookup in HeroSpec registry.
  - Browser visibility via local `_browserExpanded` bool (no full provider watch).
  - Animation controllers reduced: immersive (1), browserSlide (1), hero-specific (0–2).
  - Settings notifier read once at top level; individual section widgets use local state / Selector.
  - Mechanism: Extract hero selection into pure `heroForType(ScreenType)` function; immersive animation as a separate widget.

- **`screens/help.dart`** (~170 LOC): unchanged from `help_screen.dart`.

- **`screens/log.dart`** (~231 LOC): unchanged from `log_screen.dart`.

#### Bootstrap & Main (~150 LOC)

- **`app.dart`** (NEW, ~80 LOC, from `main.dart` 264): NothingApp + provider setup. Cleaner orchestration.

- **`main.dart`** (NEW, ~70 LOC): Entry point, splash, microtask bootstrap, cold-start optimization.

- **`debug_hooks.dart`** (~28 LOC): unchanged.

#### Theme (~150 LOC)

- **`theme/system.dart`** (NEW, ~50 LOC): ThemeSystem singleton (replaces `themes.dart` + palette/typography/geometry passthrough).

- **`theme/palette.dart`** (NEW, ~50 LOC): Light / Dark palette defs (from `palettes/*.dart`).

- **`theme/layout.dart`** (NEW, ~50 LOC): Geometry + Typography consolidated.

---

### Proposed LOC Budget

| Module | Current LOC | Proposed LOC | Reduction | Notes |
|--------|-------------|--------------|-----------|-------|
| **Services** | 4,081 | 2,200 | 1,881 (46%) | Eliminate ValueNotifier boilerplate; split monolithic files. |
| **Providers** | 434 | 200 | 234 (54%) | Inline into services; remove redundant mirroring. |
| **Controllers** | 591 | 350 | 241 (41%) | Split into library submodules. |
| **Models** | 766 | 450 | 316 (41%) | Data-driven Setting<T> replaces enum/JSON boilerplate. |
| **Widgets** | 3,885 | 1,650 | 2,235 (58%) | Split god widgets; pure row builders; remove hero duplication. |
| **Screens** | 906 | 250 | 656 (72%) | Simplify orchestration; reduce animation controllers. |
| **Theme** | 327 | 150 | 177 (54%) | Unify palette/typography/geometry lookup. |
| **Main & Debug** | 292 | 150 | 142 (49%) | Clean bootstrap; reduce debug surface. |
| **TOTAL** | **11,878** | **5,400** | **6,478 (55%)** | **Target: <6,200. Achievable with additional extraction.** |

**Additional optimizations to reach <6,200**:
- Inline small helpers (mid_ellipsis, phone_frame, retro_ticker) into parent widgets: ~250 LOC
- Extract shared gesture / animation primitives: ~100 LOC saved across VoidScreen, heroes, browser.
- Consolidate logging service into diagnostics module: ~40 LOC.

**Revised target**: **5,050 LOC** (57% reduction from 11,878).

---

## 4. MIGRATION PLAN: Current → Proposed

### Phase 1: Data & Services Refactoring (Lowest Risk)

**New modules** (no breaking changes):
1. `models/setting.dart` + `Setting<T>` / `SettingRegistry<T>`
2. `models/enums.dart` — consolidate all enums
3. `services/settings.dart` — SettingsRepository + SettingRegistry
4. `services/playback/` — modularize playback stack
5. `services/library/` — decompose LibraryController

**Mechanism**: Keep old SettingsService as facade; wire it through SettingRegistry internally. Existing notifiers still work (listen to registry streams).

**Tests to rewrite**:
- `settings_service_test.dart` (13,798 LOC): Replace with `setting_registry_test.dart` (200 LOC) — test Setting<T> type erasure, persistence, Selector.
- `library_controller_*_test.dart` (3 files, ~10 KLOC): Split into 4 module tests (navigator, search, permissions, browser).

### Phase 2: Widget Refactoring (Medium Risk)

**New modules**:
1. `ui/settings_sheet.dart` — SettingRow, SettingSection (pure builders from Setting<T> descriptors)
2. `ui/browser.dart` — BrowserListItem, BrowserSearch, BrowserPane
3. Inline theme lookup into ThemeContext helper

**Mechanism**: Old VoidBrowser / VoidSettingsSheet kept briefly; new panes used in VoidScreen; old removed when new are proven.

**Tests to rewrite**:
- `void_settings_sheet_test.dart`: Rewrite against SettingRow / SettingSection.
- `void_browser_test.dart`: Rewrite against BrowserListItem / BrowserPane.

### Phase 3: Orchestration Refactoring (Highest Risk)

**New modules**:
1. `screens/home.dart` (simplified VoidScreen)
2. `ui/skins/` — pure-function heroes
3. `ui/playback_notifier.dart` — eliminate AudioPlayerProvider

**Mechanism**: Hot-reload compatible: VoidScreen gradually shifts animation/listener logic to child widgets. Provider swap last.

**Tests to rewrite**:
- `media_controller_page_test.dart`: Route through home.dart instead.

### Phase 4: Integration & Cleanup

- Remove old files.
- Run full test suite.
- Measure LOC: target <5,500.

---

## 5. TOP 5 REDESIGN MOVES (By Lines Saved / Risk)

### 1. **SettingRegistry<T>: Eliminate 15 Hand-Written ValueNotifiers** (Saves ~200 LOC, Risk: Low)

**Current state**:
```dart
// SettingsService (542 LOC)
final ValueNotifier<BarCount> barCountNotifier = ValueNotifier(...);
final ValueNotifier<SpectrumColorScheme> colorSchemeNotifier = ValueNotifier(...);
// ... 13 more, each with getter/setter/load/save glue
```

**Proposed**:
```dart
// Setting<T> (generic descriptor)
class Setting<T> {
  final String key;
  final T defaultValue;
  final String? label;
  final T Function(String)? fromJson;
  final String Function(T)? toJson;
  // ...
}

// SettingRegistry (in-memory + persistence)
class SettingRegistry {
  Stream<T> watch<T>(String key);
  T get<T>(String key);
  Future<void> set<T>(String key, T value);
  // persists auto-magically
}

// Usage
final barCount = registry.watch<BarCount>('barCount'); // returns Stream<BarCount>
// UI subscribes via Selector; only that field rebuilds on change
```

**Impact**:
- Remove 15 notifiers + 30 getters/setters + load/save logic from SettingsService.
- New file (models/setting.dart): ~120 LOC.
- Old SettingsService shrinks: 542 → 250 LOC.
- **Total save: 200 LOC**.

**Risk**: Low — Setting<T> is isolated; old code can migrate gradually via facade.

**Tests**:
- `settings_service_test.dart` (13,798 LOC) → `setting_registry_test.dart` (200 LOC): Test Setting<T> codec, persistence, Selector reactive binding.

---

### 2. **God Widget Decomposition: VoidBrowser 837 → 350 LOC, VoidSettingsSheet 786 → 250 LOC** (Saves ~1,023 LOC, Risk: Medium)

**Current state**:
- VoidBrowser: Layout + folder listing + search in one 837-LOC file.
- VoidSettingsSheet: 15 settings groups, each manually wired cycle/slider/toggle + row builders duplicated per group.

**Proposed**:

*BrowserListItem* (pure):
```dart
@immutable
class BrowserListItem extends StatelessWidget {
  final FolderNode folder;
  final bool isSelected;
  final VoidCallback onTap;
  // renders a row with folder icon + name + optional metadata
}
```

*BrowserPane* (stateful, ~180 LOC):
```dart
class BrowserPane extends StatefulWidget {
  // orchestrates ListItem builder, search input, breadcrumb
  // _BrowserPaneState._buildFolderList() → ListView of BrowserListItem
  // _BrowserPaneState._onSearch() → debounced SearchEngine call
}
```

*SettingRow* (pure, ~40 LOC):
```dart
@immutable
class SettingRow<T> extends StatelessWidget {
  final Setting<T> setting;
  final T value;
  final ValueChanged<T> onChanged;
  // renders cycle / slider / toggle based on setting.type
}
```

*SettingsPane* (stateful, ~170 LOC):
```dart
class SettingsPane extends StatefulWidget {
  // reads SettingRegistry, builds SettingRow for each setting
  // groups via SettingSection
  // permission checks via local state (not full rebuild)
}
```

**Impact**:
- VoidBrowser: Extract BrowserListItem + BrowserSearch + BrowserPane → 837 LOC shrinks to ~350 LOC (list layout + search orchestration).
- VoidSettingsSheet: Replace manual row builders with SettingRow<T> → 786 LOC shrinks to ~250 LOC (group layout + permission checks).
- New pure widgets (BrowserListItem, SettingRow, SettingSection): ~180 LOC total.
- **Total save: 1,023 LOC**.

**Risk**: Medium — State management and event flow must be carefully threaded. Tests must cover BrowserPane + SettingsPane orchestration.

**Tests**:
- `void_browser_test.dart` (new): Test BrowserListItem rendering, BrowserPane folder navigation, search debouncing.
- `void_settings_sheet_test.dart` (new): Test SettingRow type dispatch, SettingsPane section grouping, permission checks.

---

### 3. **ScreenConfig Polymorphism → Data-Driven Config** (Saves ~200 LOC, Risk: Low)

**Current state**:
- ScreenConfig: sealed base class (7 LOC)
- 4 subclasses: SpectrumScreenConfig (77 LOC), PoloScreenConfig, DotScreenConfig, VoidScreenConfig — each with toJson, fromJson, copyWith.
- Total: 287 LOC for 4 classes with mostly duplicated structure.

**Proposed**:
```dart
@immutable
class ScreenLayout {
  final ScreenType type;
  final Map<String, dynamic> config; // per-skin fields as opaque map
  
  // Accessor getters:
  double? get spectrumWidthFactor => config['spectrumWidthFactor'] as double?;
  // etc.
  
  // Generic fromJson / toJson
  Map<String, dynamic> toJson() => {'type': type.name, ...config};
  factory ScreenLayout.fromJson(...) { ... }
  
  ScreenLayout copyWith({...}) { ... }
}
```

**Impact**:
- Replace 4 subclasses + polymorphic JSON with single flat class: 287 → 80 LOC.
- New file (models/screen.dart): ~80 LOC.
- SettingsService can treat all skins uniformly (no type-specific load/save logic).
- **Total save: 200 LOC**.

**Risk**: Low — Accessor getters maintain API compatibility; no behavioral change.

**Tests**:
- `screen_config_test.dart`: Rewrite against new ScreenLayout; test JSON round-trip for all skin configs.

---

### 4. **AudioPlayerProvider Elimination: Inline into PlaybackController** (Saves ~250 LOC, Risk: Medium)

**Current state**:
- AudioPlayerProvider (434 LOC): Pure wrapper over PlaybackController, mirrors state reactively (8 getters + stream subscriptions).
- PlaybackController (1,096 LOC): Real playback logic.
- Providers are created anew and disposed per hot-reload; state loss issue on Android.

**Proposed**:
```dart
// PlaybackController becomes a ChangeNotifier itself
class PlaybackController extends ChangeNotifier {
  // existing logic + notifyListeners() calls on state change
  
  // expose getters directly (no extra layer)
  SongInfo? get songInfo { ... }
  bool get isPlaying { ... }
  // etc.
}

// UI widget watchers:
// Old: context.watch<AudioPlayerProvider>().songInfo
// New: context.watch<PlaybackController>().songInfo
```

**Impact**:
- Eliminate AudioPlayerProvider file (434 LOC).
- PlaybackController inline state notifications: +30 LOC.
- Update all UI imports: providers/audio_player_provider → services/playback_controller.
- New PlaybackNotifier wrapper (80 LOC) for provider-compatible API if needed short-term.
- **Total save: 250 LOC**.

**Risk**: Medium — All UI consumers of AudioPlayerProvider must be updated. Android handler state-mirroring must still work (no behavior change).

**Tests**:
- `audio_player_provider_test.dart`: Merge into `playback_controller_test.dart`.

---

### 5. **LibraryController Decomposition: 591 → 150 LOC Core** (Saves ~280 LOC, Risk: Medium)

**Current state**:
- LibraryController (591 LOC): Monolithic blob mixing folder navigation, search, Android permissions, MediaStore refresh.

**Proposed**:
```dart
// FolderNavigator (new, ~150 LOC)
class FolderNavigator {
  Future<void> loadFolder(String path);
  Future<void> navigate(String path);
  String? get currentPath { ... }
  List<String> get breadcrumb { ... }
}

// SearchEngine (new, ~100 LOC)
class SearchEngine {
  Stream<List<SearchResult>> search(String query);
  void cancel();
}

// PermissionManager (new, ~80 LOC)
class PermissionManager {
  Future<bool> checkAudioPermission();
  Future<bool> requestAudioPermission();
}

// LibraryController becomes a thin orchestrator (~150 LOC)
class LibraryController {
  final FolderNavigator navigator;
  final SearchEngine search;
  final PermissionManager permissions;
  // delegates to submodules
}
```

**Impact**:
- LibraryController shrinks: 591 → 150 LOC (orchestration only).
- New files: FolderNavigator, SearchEngine, PermissionManager: ~330 LOC.
- Each submodule testable in isolation.
- Reusability: PermissionManager can be used elsewhere; SearchEngine decoupled from UI.
- **Total save: 280 LOC** (590 - 310 new lines).

**Risk**: Medium — Careful state threading between navigator/search/permissions. Each module must handle its own async lifecycle.

**Tests**:
- `library_controller_test.dart` → 4 new test files (navigator, search, permissions, orchestration).

---

## 6. SUMMARY TABLE

| Move | Current LOC | Proposed LOC | Saving | Feature Impact | Test Rewrites |
|------|-------------|--------------|--------|-----------------|---------------|
| 1. SettingRegistry | 542 (settings) | 250 | 200 | None; faster rebuild | settings_service_test → setting_registry_test |
| 2. God Widget Split | 837 + 786 = 1,623 | 600 | 1,023 | None; better composability | void_browser_test, void_settings_sheet_test (completely new) |
| 3. ScreenLayout | 287 | 80 | 200 | None; unified config | screen_config_test (rewritten) |
| 4. Provider Inline | 434 | 0 | 250 | None; cleaner API | audio_player_provider_test → playback_controller_test |
| 5. LibraryController | 591 | 150 | 280 | None; better separation | library_controller_test → 4 submodule tests |
| **TOTAL** | **4,080** | **1,080** | **2,253** | **None** | **~1,200 LOC test rewrites** |

**Remaining lib/ (as-is, not redesigned)**:
- Screens (help, log): 401 LOC (no change)
- Unchanged services: 1,200 LOC (audio focus, platform channels, metadata, etc.)
- Theme: 327 LOC (minor consolidation, ~200 final)
- Models (small): 300 LOC (unchanged)
- Main / Bootstrap: 292 LOC (minor; ~150 final)

**Conservative estimate**:
- Redesign savings: 2,253 LOC
- Remaining / new code: 3,150 LOC
- **Final lib/**: ~5,900 LOC ✓ (target: <6,200)

**Optimistic estimate** (with additional inlining + extraction):
- Add inline mid_ellipsis, phone_frame, retro_ticker: ~250 LOC saved
- Extract gesture/animation primitives: ~100 LOC saved
- Consolidate logging: ~40 LOC saved
- **Final lib/**: ~5,410 LOC

---

## 7. RISK ASSESSMENT & MITIGATION

### High-Risk Moves

1. **VoidScreen Simplification** (Phase 3)
   - Risk: Immersive animation, swipe-up browser slide, transport positioning are tightly coupled.
   - Mitigation: Refactor in discrete steps; keep animations unchanged first, then extract.

2. **Provider Swap** (AudioPlayerProvider → PlaybackController ChangeNotifier)
   - Risk: All UI consumers change import path; hot-reload state loss on Android.
   - Mitigation: Phased swap; new PlaybackNotifier facade for transition period; test end-to-end on real device.

3. **SettingRegistry Introduction**
   - Risk: Old ValueNotifier API must stay compatible; migration from old to new notifiers must not lose subscriber state.
   - Mitigation: SettingRegistry wraps SharedPreferences directly; old SettingsService listens to registry streams internally, maintaining backward compatibility.

### Testing Strategy

- **Unit tests**: Test each new module in isolation (Setting<T>, FolderNavigator, SearchEngine, SettingRow, BrowserPane).
- **Integration tests**: VoidScreen orchestration with new providers; hero selection + browser toggling.
- **Regression tests**: Run existing playback, library, settings test suite against new code; ensure behavior identical.
- **Device tests**: Audio playback, MediaSession, permissions on Android; immersive mode on all platforms.

### Rollback Plan

Each phase is self-contained:
- Phase 1 (services): Old SettingsService facade masks new SettingRegistry; can revert mid-migration.
- Phase 2 (widgets): Old VoidBrowser / VoidSettingsSheet remain; new panes run in parallel until proven.
- Phase 3 (orchestration): VoidScreen refactoring last; keep old version in git branch until full test pass.

---

## 8. ACCEPTANCE CRITERIA

### Functional

- [ ] All 28 golden requirements preserved (playback, queue, search, visualizer, skins, settings, diagnostics, Android session).
- [ ] All regression tests pass (including playback, interruption, skip-on-error, search-session, one-shot, skip-bug, permission, mediastore-refresh).
- [ ] All unit tests rewritten and passing.
- [ ] No new bugs introduced in exploratory testing.

### Performance

- [ ] Cold start time: ≤350 ms (first frame, debug emulator).
- [ ] Settings change: no perceptible stutter (< 16 ms frame time).
- [ ] Search query: < 200 ms latency (on folder with 1K+ files).

### Code Quality

- [ ] lib/ < 6,200 LOC (target: 5,400–5,900).
- [ ] No file > 400 LOC (except PlaybackController ~900, VoidScreen ~300, SettingsService ~250; justified by complexity).
- [ ] Cyclomatic complexity < 10 per method (static analyzer pass).
- [ ] All public APIs documented (dartdoc).

---

## 9. SUPPORTING DOCUMENTS

- [Architecture: Audio Playback & Spectrum](audio-playback-spectrum.md)
- [Architecture: Library Browsing](library-browsing.md)
- [Architecture: UI Scaling](ui-scaling.md)
- [Architecture: Skins](skins.md)
- [Testing Standards](../.cursor/rules/testing-standards.mdc)

