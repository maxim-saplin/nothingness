import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/operating_mode.dart';
import '../models/screen_config.dart';
import '../models/eq_settings.dart';
import '../models/spectrum_settings.dart';
import '../models/theme_id.dart';
import '../models/theme_variant.dart';
import '../models/transport_position.dart';
import 'platform_channels.dart';

class SettingsService {
  // Singleton
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _settingsKey = 'spectrum_settings';
  static const String _uiScaleKey = 'ui_scale';
  static const String _screenConfigKey = 'screen_config';
  static const String _fullScreenKey = 'full_screen';
  static const String _useFilenameForMetadataKey = 'use_filename_for_metadata';
  static const String _eqSettingsKey = 'eq_settings';
  static const String _audioDiagnosticsOverlayKey = 'audio_diagnostics_overlay';
  static const String _themeIdKey = 'theme_id';
  static const String _themeVariantKey = 'theme_variant';
  static const String _operatingModeKey = 'operating_mode';
  static const String _smartFoldersPresentationKey = 'smart_folders_presentation';
  static const String _immersiveKey = 'immersive';
  static const String _transportVisibleKey = 'transport_visible';
  static const String _transportPositionKey = 'transport_position';
  static const String _lastLibraryPathKey = 'last_library_path';

  // --- APP DEFAULTS (Single Source of Truth) ---
  static const double defaultNoiseGateDb = -35.0;
  static const BarCount defaultBarCount = BarCount.bars24;
  static const SpectrumColorScheme defaultColorScheme =
      SpectrumColorScheme.classic;
  static const BarStyle defaultBarStyle = BarStyle.segmented;
  static const DecaySpeed defaultDecaySpeed = DecaySpeed.medium;
  static const double defaultUiScale = -1.0; // -1.0 indicates "auto" / not set
  static const bool defaultFullScreen = false;
  static const bool defaultUseFilenameForMetadata = true;
  static const ScreenConfig defaultScreenConfig = SpectrumScreenConfig();
  static const bool defaultEqEnabled = false;
  static const bool defaultAudioDiagnosticsOverlay = false;
  static const ThemeId defaultThemeId = ThemeId.void_;
  static const ThemeVariant defaultThemeVariant = ThemeVariant.system;
  static const OperatingMode defaultOperatingMode = OperatingMode.own;
  static const bool defaultSmartFoldersPresentation = true;
  static const bool defaultImmersive = false;
  static const bool defaultTransportVisible = true;
  static const TransportPosition defaultTransportPosition =
      TransportPosition.bottom;

  /// Light scrim drawn behind dark OEM status-bar icons on automotive displays.
  static const Color automotiveStatusBarScrimLight = Color(0xFFE8E8E8);

  /// Dark scrim used when system is in dark mode on automotive displays.
  static const Color automotiveStatusBarScrimDark = Color(0xFF2C2C2C);

  final ValueNotifier<SpectrumSettings> settingsNotifier = ValueNotifier(
    const SpectrumSettings(),
  );

  final ValueNotifier<EqSettings> eqSettingsNotifier = ValueNotifier(
    const EqSettings(),
  );

  final ValueNotifier<double> uiScaleNotifier = ValueNotifier(defaultUiScale);
  final ValueNotifier<bool> fullScreenNotifier = ValueNotifier(
    defaultFullScreen,
  );
  final ValueNotifier<bool> useFilenameForMetadataNotifier = ValueNotifier(
    defaultUseFilenameForMetadata,
  );
  final ValueNotifier<ScreenConfig> screenConfigNotifier = ValueNotifier(
    defaultScreenConfig,
  );
  final ValueNotifier<bool> debugLayoutNotifier = ValueNotifier(false);
  final ValueNotifier<bool> audioDiagnosticsOverlayNotifier = ValueNotifier(
    defaultAudioDiagnosticsOverlay,
  );
  final ValueNotifier<ThemeId> themeIdNotifier = ValueNotifier(defaultThemeId);
  final ValueNotifier<ThemeVariant> themeVariantNotifier = ValueNotifier(
    defaultThemeVariant,
  );
  final ValueNotifier<OperatingMode> operatingModeNotifier = ValueNotifier(
    defaultOperatingMode,
  );

  /// Whether the library surfaces should present "smart" friendly labels for
  /// Android storage roots (Internal, USB, SD card, …) instead of raw paths.
  /// P5 owns the helper that reads this notifier; P4 only exposes the toggle.
  final ValueNotifier<bool> smartFoldersPresentationNotifier = ValueNotifier(
    defaultSmartFoldersPresentation,
  );

  /// Immersive mode for the Void chrome: hides the browser, crumb, transport
  /// row, settings glyph and progress hairline so the hero fills the screen.
  /// Driven by the LOOK row in `VoidSettingsSheet`; replaces the previous
  /// drag-down gesture so it doesn't fight with hero swipe-to-skip.
  final ValueNotifier<bool> immersiveNotifier = ValueNotifier(defaultImmersive);

  /// Where the prev / play-pause / next transport strip is anchored —
  /// [TransportPosition.bottom] (above the crumb), [TransportPosition.top]
  /// (pinned to the top of the browser band, immediately below the hero),
  /// or [TransportPosition.off] (hidden). The previous bool-valued
  /// `transportVisibleNotifier` (legacy 'transport_visible' pref) is
  /// migrated into this on first load.
  final ValueNotifier<TransportPosition> transportPositionNotifier =
      ValueNotifier(defaultTransportPosition);

  /// Heuristic: low-DPI (< 2.0) + wide (>= 1600 logical) = automotive / IVI.
  ///
  /// Phone displays are high-DPI (>= 2.0) so they never match.
  /// Known automotive displays:
  ///   - Zeekr DHU: 2560x1600 @ 160dpi (DPR 1.0, logical width 2560)
  ///   - Typical IVI: 1920x720 @ 160dpi (DPR 1.0, logical width 1920)
  static bool isLikelyAutomotive(double logicalWidth, double devicePixelRatio) {
    return devicePixelRatio < 2.0 && logicalWidth >= 1600;
  }

  /// Calculates a smart UI scale based on logical width and device pixel ratio.
  ///
  /// - [logicalWidth]: The width of the screen in logical pixels.
  /// - [devicePixelRatio]: The density of the screen (default 1.0).
  ///
  /// Logic:
  /// - Automotive (Low DPI + width in typical car range): Target ~850dp.
  /// - Tablets (High DPI OR very wide low-DPI): Target ~960dp.
  double calculateSmartScaleForWidth(
    double logicalWidth, {
    double devicePixelRatio = 1.0,
  }) {
    // Guard against invalid width; fall back to no scaling.
    if (logicalWidth <= 0) {
      return 1.0;
    }

    // Heuristic: low DPI (< 2.0) + wide (>= 1600) = automotive.
    // Automotive displays: 1920x720, 2560x1600, etc. at ~160dpi (DPR ~1.0).
    // Use 800 target for large touch targets on automotive.
    // Use 960 target for balanced information density on tablets/phones.
    final bool isAutomotive =
        SettingsService.isLikelyAutomotive(logicalWidth, devicePixelRatio);
    final double targetWidth = isAutomotive ? 800.0 : 960.0;

    // Calculate scale
    final double scale = logicalWidth / targetWidth;

    // Clamp values:
    // - Min 1.0: Don't shrink UI on phones (width < target)
    // - Max 3.0: Don't let it get absurdly huge
    return scale.clamp(1.0, 3.0);
  }

  /// Loads settings from persistence, or returns defaults if none exist.
  Future<SpectrumSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Load Spectrum Settings
    final jsonString = prefs.getString(_settingsKey);
    SpectrumSettings settings;
    if (jsonString != null) {
      try {
        settings = SpectrumSettings.fromJson(jsonDecode(jsonString));
      } catch (e) {
        settings = const SpectrumSettings();
      }
    } else {
      settings = const SpectrumSettings();
    }
    settingsNotifier.value = settings;

    // 1b. Load EQ Settings
    final eqJsonString = prefs.getString(_eqSettingsKey);
    EqSettings eqSettings;
    if (eqJsonString != null) {
      try {
        eqSettings = EqSettings.fromJson(jsonDecode(eqJsonString));
      } catch (e) {
        eqSettings = const EqSettings();
      }
    } else {
      eqSettings = const EqSettings();
    }
    eqSettingsNotifier.value = eqSettings;

    // 2. Load UI Scale (with migration)
    if (prefs.containsKey(_uiScaleKey)) {
      final loadedScale = prefs.getDouble(_uiScaleKey) ?? defaultUiScale;
      debugPrint('[UI Scale] Loaded from prefs: $loadedScale');
      uiScaleNotifier.value = loadedScale;
    } else {
      // Migration: Check if it was in the old JSON
      if (jsonString != null) {
        try {
          final json = jsonDecode(jsonString);
          final oldScale =
              (json['uiScale'] as num?)?.toDouble() ??
              (json['textScale'] as num?)?.toDouble();

          if (oldScale != null) {
            debugPrint('[UI Scale] Migrated from JSON: $oldScale');
            uiScaleNotifier.value = oldScale;
            // Persist to new key immediately
            await prefs.setDouble(_uiScaleKey, oldScale);
          } else {
            debugPrint(
              '[UI Scale] No saved value, using default: $defaultUiScale',
            );
            uiScaleNotifier.value = defaultUiScale;
          }
        } catch (_) {
          uiScaleNotifier.value = defaultUiScale;
        }
      } else {
        debugPrint('[UI Scale] Fresh install, using default: $defaultUiScale');
        uiScaleNotifier.value = defaultUiScale;
      }
    }

    // 3. Load Screen Config
    final screenJsonString = prefs.getString(_screenConfigKey);
    if (screenJsonString != null) {
      try {
        final json = jsonDecode(screenJsonString);
        screenConfigNotifier.value = ScreenConfig.fromJson(json);
      } catch (e) {
        debugPrint('Error loading screen config: $e');
        screenConfigNotifier.value = defaultScreenConfig;
      }
    } else {
      screenConfigNotifier.value = defaultScreenConfig;
    }

    // 4. Load Full Screen
    final isFullScreen = prefs.getBool(_fullScreenKey) ?? defaultFullScreen;
    fullScreenNotifier.value = isFullScreen;
    // Apply system UI mode (without saving again)
    setFullScreen(isFullScreen, save: false);

    // 5. Load Use Filename For Metadata
    final useFilenameForMetadata =
        prefs.getBool(_useFilenameForMetadataKey) ?? defaultUseFilenameForMetadata;
    useFilenameForMetadataNotifier.value = useFilenameForMetadata;

    // 6. Load Audio Diagnostics Overlay flag
    audioDiagnosticsOverlayNotifier.value =
        prefs.getBool(_audioDiagnosticsOverlayKey) ??
            defaultAudioDiagnosticsOverlay;

    // 6b. Load Smart Folders Presentation toggle (P4 wires the toggle; P5
    //     consumes it from the smart-roots labelling helper).
    smartFoldersPresentationNotifier.value =
        prefs.getBool(_smartFoldersPresentationKey) ??
            defaultSmartFoldersPresentation;

    // 6c. Load Immersive toggle (Void chrome hides browser/crumb/transport
    //     when true). Defaults off on fresh install.
    immersiveNotifier.value = prefs.getBool(_immersiveKey) ?? defaultImmersive;

    // 6d. Load Transport position (top / bottom / off). One-shot migration
    //     from the legacy 'transport_visible' bool key when the new key
    //     hasn't been set yet: true → bottom (default), false → off.
    if (prefs.containsKey(_transportPositionKey)) {
      transportPositionNotifier.value = TransportPositionX.fromStorageKey(
        prefs.getString(_transportPositionKey),
      );
    } else if (prefs.containsKey(_transportVisibleKey)) {
      final legacy = prefs.getBool(_transportVisibleKey) ?? true;
      final migrated =
          legacy ? TransportPosition.bottom : TransportPosition.off;
      await prefs.setString(_transportPositionKey, migrated.storageKey);
      await prefs.remove(_transportVisibleKey);
      transportPositionNotifier.value = migrated;
    } else {
      transportPositionNotifier.value = defaultTransportPosition;
    }

    // 7. Load Theme id + variant.
    themeIdNotifier.value = ThemeId.fromStorageKey(prefs.getString(_themeIdKey));
    themeVariantNotifier.value =
        ThemeVariant.fromStorageKey(prefs.getString(_themeVariantKey));

    // 8. Load Operating Mode (with one-shot migration from legacy
    //    spectrum_settings.audioSource — runs only when the new key is
    //    absent; subsequent loads are idempotent).
    if (prefs.containsKey(_operatingModeKey)) {
      operatingModeNotifier.value =
          OperatingMode.fromStorageKey(prefs.getString(_operatingModeKey));
    } else {
      OperatingMode mode = defaultOperatingMode;
      if (jsonString != null) {
        try {
          final json = jsonDecode(jsonString) as Map<String, dynamic>;
          final legacy = json['audioSource'] as String?;
          if (legacy != null) {
            mode = legacy == 'microphone'
                ? OperatingMode.background
                : OperatingMode.own;
            // Strip the legacy field from the persisted JSON so the
            // migration cannot run twice.
            json.remove('audioSource');
            await prefs.setString(_settingsKey, jsonEncode(json));
            debugPrint(
              '[Settings] Migrated audioSource=$legacy -> '
              'operatingMode=${mode.name}',
            );
          }
        } catch (_) {
          // Corrupted legacy JSON — keep default and let the new key win
          // on next save.
        }
      }
      await prefs.setString(_operatingModeKey, mode.storageKey);
      operatingModeNotifier.value = mode;
    }

    return settings;
  }

  /// Persists the active theme id.
  Future<void> saveThemeId(ThemeId id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeIdKey, id.storageKey);
    themeIdNotifier.value = id;
  }

  /// Persists the active theme variant (dark / light / system).
  Future<void> saveThemeVariant(ThemeVariant variant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeVariantKey, variant.storageKey);
    themeVariantNotifier.value = variant;
  }

  /// Persists the operating mode (own / background).
  Future<void> saveOperatingMode(OperatingMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_operatingModeKey, mode.storageKey);
    operatingModeNotifier.value = mode;
  }

  /// Sets the audio diagnostics overlay flag.
  Future<void> setAudioDiagnosticsOverlay(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_audioDiagnosticsOverlayKey, enable);
    audioDiagnosticsOverlayNotifier.value = enable;
  }

  /// Sets the smart-folders presentation toggle. When true, library surfaces
  /// show friendly labels for Android storage roots. Owned by P5.
  Future<void> setSmartFoldersPresentation(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_smartFoldersPresentationKey, enable);
    smartFoldersPresentationNotifier.value = enable;
  }

  /// Sets the Void-chrome immersive toggle. Persists across launches.
  Future<void> setImmersive(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_immersiveKey, enable);
    immersiveNotifier.value = enable;
  }

  /// Sets the transport-strip anchor (top / bottom / off).
  Future<void> setTransportPosition(TransportPosition pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_transportPositionKey, pos.storageKey);
    transportPositionNotifier.value = pos;
  }

  /// Reads the last folder the library browser was inside before the app
  /// was suspended or closed. Returns `null` when no path has been saved
  /// (fresh install, or the user navigated back to the smart-roots view).
  Future<String?> loadLastLibraryPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastLibraryPathKey);
  }

  /// Persists the current library-browser path. Pass `null` to clear the
  /// stored value (i.e. when the user navigates up to the smart-roots view).
  Future<void> saveLastLibraryPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_lastLibraryPathKey);
    } else {
      await prefs.setString(_lastLibraryPathKey, path);
    }
  }

  /// Saves the spectrum settings to persistence.
  Future<void> saveSettings(SpectrumSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    settingsNotifier.value = settings;
  }

  /// Saves the EQ settings to persistence.
  Future<void> saveEqSettings(EqSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_eqSettingsKey, jsonEncode(settings.toJson()));
    eqSettingsNotifier.value = settings;

    // Apply immediately on Android (best-effort).
    if (PlatformChannels.isAndroid) {
      PlatformChannels().updateEqualizerSettings(settings);
    }
  }

  /// Saves the UI scale to persistence.
  Future<void> saveUiScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiScaleKey, scale);
    uiScaleNotifier.value = scale;
  }

  /// Saves the screen configuration to persistence.
  Future<void> saveScreenConfig(ScreenConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_screenConfigKey, jsonEncode(config.toJson()));
    screenConfigNotifier.value = config;
  }

  /// Toggles or sets full screen mode.
  ///
  /// - [enable]: Whether to enable immersive full screen.
  /// - [save]: Whether to persist the setting (default true).
  Future<void> setFullScreen(bool enable, {bool save = true}) async {
    if (save) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_fullScreenKey, enable);
      fullScreenNotifier.value = enable;
    }

    if (enable) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF000000),
        systemNavigationBarIconBrightness: Brightness.light,
      ));
    } else {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      final useDarkIcons = brightness == Brightness.light;

      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarColor: const Color(0x00000000),
        statusBarIconBrightness:
            useDarkIcons ? Brightness.dark : Brightness.light,
        statusBarBrightness:
            useDarkIcons ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: const Color(0xFF0A0A0F),
        systemNavigationBarIconBrightness: Brightness.light,
      ));
    }
  }

  /// Sets the use filename for metadata setting.
  Future<void> setUseFilenameForMetadata(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useFilenameForMetadataKey, enable);
    useFilenameForMetadataNotifier.value = enable;
  }

  void toggleDebugLayout() {
    debugLayoutNotifier.value = !debugLayoutNotifier.value;
  }
}
