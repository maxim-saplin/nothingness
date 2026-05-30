import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/browser_presentation.dart';
import '../models/operating_mode.dart';
import '../models/screen_config.dart';
import '../models/eq_settings.dart';
import '../models/spectrum_settings.dart';
import '../models/theme_id.dart';
import '../models/theme_variant.dart';
import '../models/transport_position.dart';
import 'platform_channels.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _settingsKey = 'spectrum_settings';
  static const String _uiScaleKey = 'ui_scale';
  /// Legacy single-blob key (pre-B-028). Kept only for one-shot migration.
  static const String _legacyScreenConfigKey = 'screen_config';
  /// Per-screen key prefix (B-028): each screen persists its own blob.
  static const String _screenConfigKeyPrefix = 'screen_config_';
  /// Active screen across launches (B-028); tells boot which key to load.
  static const String _activeScreenIdKey = 'active_screen_id';
  static const String _fullScreenKey = 'full_screen';
  /// B-042: debug-only desktop "phone frame", stored as "WxH".
  static const String _phoneFrameKey = 'phone_frame';
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
  static const String _browserPresentationKey = 'browser_presentation';
  static const String _lastLibraryPathKey = 'last_library_path';

  // App defaults (single source of truth).
  static const double defaultNoiseGateDb = -35.0;
  static const BarCount defaultBarCount = BarCount.bars24;
  static const SpectrumColorScheme defaultColorScheme =
      SpectrumColorScheme.classic;
  static const BarStyle defaultBarStyle = BarStyle.segmented;
  static const DecaySpeed defaultDecaySpeed = DecaySpeed.medium;
  static const double defaultUiScale = -1.0; // -1.0 indicates "auto" / not set
  static const bool defaultFullScreen = false;
  static const Size? defaultPhoneFrame = null; // null = off (full window)
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
  static const BrowserPresentation defaultBrowserPresentation =
      BrowserPresentation.fixed;

  /// Automotive status-bar scrims (light/dark) drawn behind OEM icons.
  static const Color automotiveStatusBarScrimLight = Color(0xFFE8E8E8);
  static const Color automotiveStatusBarScrimDark = Color(0xFF2C2C2C);

  final ValueNotifier<SpectrumSettings> settingsNotifier =
      ValueNotifier(const SpectrumSettings());
  final ValueNotifier<EqSettings> eqSettingsNotifier =
      ValueNotifier(const EqSettings());
  final ValueNotifier<double> uiScaleNotifier = ValueNotifier(defaultUiScale);
  final ValueNotifier<bool> fullScreenNotifier = ValueNotifier(defaultFullScreen);
  /// B-042: when non-null, debug desktop renders inside a letterboxed phone
  /// frame of this size (e.g. 390x844).
  final ValueNotifier<Size?> phoneFrameNotifier = ValueNotifier(defaultPhoneFrame);
  final ValueNotifier<bool> useFilenameForMetadataNotifier =
      ValueNotifier(defaultUseFilenameForMetadata);
  final ValueNotifier<ScreenConfig> screenConfigNotifier =
      ValueNotifier(defaultScreenConfig);
  final ValueNotifier<bool> debugLayoutNotifier = ValueNotifier(false);
  final ValueNotifier<bool> audioDiagnosticsOverlayNotifier =
      ValueNotifier(defaultAudioDiagnosticsOverlay);
  final ValueNotifier<ThemeId> themeIdNotifier = ValueNotifier(defaultThemeId);
  final ValueNotifier<ThemeVariant> themeVariantNotifier =
      ValueNotifier(defaultThemeVariant);
  final ValueNotifier<OperatingMode> operatingModeNotifier =
      ValueNotifier(defaultOperatingMode);

  /// When true, library surfaces show friendly labels for Android storage roots
  /// instead of raw paths. P5 owns the reader; P4 exposes the toggle.
  final ValueNotifier<bool> smartFoldersPresentationNotifier =
      ValueNotifier(defaultSmartFoldersPresentation);

  /// Immersive Void chrome: hides browser, crumb, transport, settings glyph and
  /// progress hairline so the hero fills the screen. Driven by the LOOK row.
  final ValueNotifier<bool> immersiveNotifier = ValueNotifier(defaultImmersive);

  /// Transport strip anchor (bottom / top / off). Migrated on first load from
  /// the legacy bool `transport_visible` pref.
  final ValueNotifier<TransportPosition> transportPositionNotifier =
      ValueNotifier(defaultTransportPosition);

  /// Whether the browser is permanently visible or swipe-up revealed.
  final ValueNotifier<BrowserPresentation> browserPresentationNotifier =
      ValueNotifier(defaultBrowserPresentation);

  /// Heuristic: low-DPI (< 2.0) + wide (>= 1600 logical) = automotive / IVI
  /// (phones are high-DPI so never match). E.g. Zeekr DHU 2560x1600@160dpi.
  static bool isLikelyAutomotive(double logicalWidth, double devicePixelRatio) =>
      devicePixelRatio < 2.0 && logicalWidth >= 1600;

  /// Smart UI scale from [logicalWidth] + [devicePixelRatio]: automotive targets
  /// ~800dp (large touch targets), tablets/phones ~960dp. Clamped 1.0..3.0.
  double calculateSmartScaleForWidth(
    double logicalWidth, {
    double devicePixelRatio = 1.0,
  }) {
    if (logicalWidth <= 0) return 1.0;
    final target =
        isLikelyAutomotive(logicalWidth, devicePixelRatio) ? 800.0 : 960.0;
    return (logicalWidth / target).clamp(1.0, 3.0);
  }

  /// Reads [key], runs [parse]; returns [fallback] if absent or parse throws.
  T _loadOrDefault<T>(
    SharedPreferences p,
    String key,
    T Function(String) parse,
    T fallback,
  ) {
    final raw = p.getString(key);
    if (raw == null) return fallback;
    try {
      return parse(raw);
    } catch (_) {
      return fallback;
    }
  }

  /// Loads settings from persistence, or returns defaults if none exist.
  Future<SpectrumSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_settingsKey);

    final settings = _loadOrDefault(prefs, _settingsKey,
        (s) => SpectrumSettings.fromJson(jsonDecode(s)), const SpectrumSettings());
    settingsNotifier.value = settings;

    eqSettingsNotifier.value = _loadOrDefault(prefs, _eqSettingsKey,
        (s) => EqSettings.fromJson(jsonDecode(s)), const EqSettings());

    // UI scale, with one-shot migration from the old JSON blob.
    if (prefs.containsKey(_uiScaleKey)) {
      final loadedScale = prefs.getDouble(_uiScaleKey) ?? defaultUiScale;
      debugPrint('[UI Scale] Loaded from prefs: $loadedScale');
      uiScaleNotifier.value = loadedScale;
    } else {
      double scale = defaultUiScale;
      if (jsonString != null) {
        try {
          final json = jsonDecode(jsonString);
          final oldScale = (json['uiScale'] as num?)?.toDouble() ??
              (json['textScale'] as num?)?.toDouble();
          if (oldScale != null) {
            debugPrint('[UI Scale] Migrated from JSON: $oldScale');
            scale = oldScale;
            await prefs.setDouble(_uiScaleKey, oldScale);
          } else {
            debugPrint('[UI Scale] No saved value, using default: $defaultUiScale');
          }
        } catch (_) {/* keep default */}
      } else {
        debugPrint('[UI Scale] Fresh install, using default: $defaultUiScale');
      }
      uiScaleNotifier.value = scale;
    }

    // Screen config (B-028): migrate legacy single-blob key, then load active.
    await _migrateLegacyScreenConfig(prefs);
    final activeId = prefs.getString(_activeScreenIdKey);
    final activeScreen = activeId != null ? await loadScreenConfig(activeId) : null;
    screenConfigNotifier.value = activeScreen ?? defaultScreenConfig;

    final isFullScreen = prefs.getBool(_fullScreenKey) ?? defaultFullScreen;
    fullScreenNotifier.value = isFullScreen;
    setFullScreen(isFullScreen, save: false); // Apply system UI mode only.

    // Phone frame (B-042) — parse persisted "WxH" string.
    phoneFrameNotifier.value = _parsePhoneFrame(prefs.getString(_phoneFrameKey));

    useFilenameForMetadataNotifier.value =
        prefs.getBool(_useFilenameForMetadataKey) ?? defaultUseFilenameForMetadata;
    audioDiagnosticsOverlayNotifier.value =
        prefs.getBool(_audioDiagnosticsOverlayKey) ?? defaultAudioDiagnosticsOverlay;
    smartFoldersPresentationNotifier.value =
        prefs.getBool(_smartFoldersPresentationKey) ?? defaultSmartFoldersPresentation;
    immersiveNotifier.value = prefs.getBool(_immersiveKey) ?? defaultImmersive;

    // Transport position; one-shot migration from legacy 'transport_visible'
    // bool (true → bottom, false → off) when the new key is unset.
    if (prefs.containsKey(_transportPositionKey)) {
      transportPositionNotifier.value =
          TransportPositionX.fromStorageKey(prefs.getString(_transportPositionKey));
    } else if (prefs.containsKey(_transportVisibleKey)) {
      final legacy = prefs.getBool(_transportVisibleKey) ?? true;
      final migrated = legacy ? TransportPosition.bottom : TransportPosition.off;
      await prefs.setString(_transportPositionKey, migrated.storageKey);
      await prefs.remove(_transportVisibleKey);
      transportPositionNotifier.value = migrated;
    } else {
      transportPositionNotifier.value = defaultTransportPosition;
    }

    browserPresentationNotifier.value =
        BrowserPresentationX.fromStorageKey(prefs.getString(_browserPresentationKey));
    themeIdNotifier.value = ThemeId.fromStorageKey(prefs.getString(_themeIdKey));
    themeVariantNotifier.value =
        ThemeVariant.fromStorageKey(prefs.getString(_themeVariantKey));

    // Operating mode; one-shot migration from legacy spectrum_settings
    // .audioSource when the new key is absent (idempotent thereafter).
    if (prefs.containsKey(_operatingModeKey)) {
      operatingModeNotifier.value =
          OperatingMode.fromStorageKey(prefs.getString(_operatingModeKey));
    } else {
      var mode = defaultOperatingMode;
      if (jsonString != null) {
        try {
          final json = jsonDecode(jsonString) as Map<String, dynamic>;
          final legacy = json['audioSource'] as String?;
          if (legacy != null) {
            mode = legacy == 'microphone'
                ? OperatingMode.background
                : OperatingMode.own;
            // Strip legacy field so the migration can't run twice.
            json.remove('audioSource');
            await prefs.setString(_settingsKey, jsonEncode(json));
            debugPrint(
                '[Settings] Migrated audioSource=$legacy -> operatingMode=${mode.name}');
          }
        } catch (_) {
          // Corrupted legacy JSON — keep default; new key wins on next save.
        }
      }
      await prefs.setString(_operatingModeKey, mode.storageKey);
      operatingModeNotifier.value = mode;
    }

    return settings;
  }

  /// Persists [value] as a bool under [key] and mirrors it into [notifier].
  Future<void> _saveBool(
      String key, bool value, ValueNotifier<bool> notifier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    notifier.value = value;
  }

  /// Persists [value]'s `storageKey` under [key] and mirrors it into [notifier].
  Future<void> _saveStorageKey<T>(
      String key, T value, String storageKey, ValueNotifier<T> notifier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, storageKey);
    notifier.value = value;
  }

  /// Persists the active theme id.
  Future<void> saveThemeId(ThemeId id) =>
      _saveStorageKey(_themeIdKey, id, id.storageKey, themeIdNotifier);

  /// Persists the active theme variant (dark / light / system).
  Future<void> saveThemeVariant(ThemeVariant variant) => _saveStorageKey(
      _themeVariantKey, variant, variant.storageKey, themeVariantNotifier);

  /// Persists the operating mode (own / background).
  Future<void> saveOperatingMode(OperatingMode mode) => _saveStorageKey(
      _operatingModeKey, mode, mode.storageKey, operatingModeNotifier);

  /// Sets the audio diagnostics overlay flag.
  Future<void> setAudioDiagnosticsOverlay(bool enable) => _saveBool(
      _audioDiagnosticsOverlayKey, enable, audioDiagnosticsOverlayNotifier);

  /// Sets the smart-folders presentation toggle (friendly storage-root labels).
  Future<void> setSmartFoldersPresentation(bool enable) => _saveBool(
      _smartFoldersPresentationKey, enable, smartFoldersPresentationNotifier);

  /// Sets the Void-chrome immersive toggle. Persists across launches.
  Future<void> setImmersive(bool enable) =>
      _saveBool(_immersiveKey, enable, immersiveNotifier);

  /// Sets the transport-strip anchor (top / bottom / off).
  Future<void> setTransportPosition(TransportPosition pos) => _saveStorageKey(
      _transportPositionKey, pos, pos.storageKey, transportPositionNotifier);

  /// Sets the browser-presentation mode (fixed vs swipe-up).
  Future<void> setBrowserPresentation(BrowserPresentation p) => _saveStorageKey(
      _browserPresentationKey, p, p.storageKey, browserPresentationNotifier);

  /// Reads the last library-browser folder; `null` when none saved.
  Future<String?> loadLastLibraryPath() async =>
      (await SharedPreferences.getInstance()).getString(_lastLibraryPathKey);

  /// Persists the current library-browser path; pass `null` to clear it.
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

  /// Maps a [ScreenType] to its per-screen storage suffix (B-028); strips the
  /// trailing-underscore keyword workaround so `void_` reads as `void`.
  static String screenIdForType(ScreenType type) {
    final raw = type.name;
    return raw.endsWith('_') ? raw.substring(0, raw.length - 1) : raw;
  }

  /// Storage key for the given [screenId]'s persisted config blob.
  static String _keyForScreenId(String screenId) =>
      '$_screenConfigKeyPrefix$screenId';

  /// Saves [config] under its per-screen key (`screen_config_<id>`) and records
  /// it as active. B-028: each screen has its own slot, no sibling clobbering.
  Future<void> saveScreenConfig(ScreenConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final id = screenIdForType(config.type);
    await prefs.setString(_keyForScreenId(id), jsonEncode(config.toJson()));
    await prefs.setString(_activeScreenIdKey, id);
    screenConfigNotifier.value = config;
  }

  /// Reads the persisted [ScreenConfig] for [screenId]; `null` when none saved
  /// (caller falls back to const default). Runs legacy migration first. (B-028)
  Future<ScreenConfig?> loadScreenConfig(String screenId) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyScreenConfig(prefs);
    final raw = prefs.getString(_keyForScreenId(screenId));
    if (raw == null) return null;
    try {
      return ScreenConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[Settings] Bad per-screen config for "$screenId": $e');
      return null;
    }
  }

  /// One-shot migration: legacy `screen_config` → per-screen
  /// `screen_config_<id>`. Idempotent; corrupted blobs are dropped. (B-028)
  Future<void> _migrateLegacyScreenConfig(SharedPreferences prefs) async {
    if (!prefs.containsKey(_legacyScreenConfigKey)) return;
    final raw = prefs.getString(_legacyScreenConfigKey);
    if (raw == null || raw.isEmpty) {
      await prefs.remove(_legacyScreenConfigKey);
      return;
    }
    try {
      final cfg = ScreenConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final id = screenIdForType(cfg.type);
      // Don't clobber an existing per-screen key (partial prior migration).
      if (!prefs.containsKey(_keyForScreenId(id))) {
        await prefs.setString(_keyForScreenId(id), jsonEncode(cfg.toJson()));
      }
      // Record as active so boot lands on the pre-upgrade skin.
      if (!prefs.containsKey(_activeScreenIdKey)) {
        await prefs.setString(_activeScreenIdKey, id);
      }
      debugPrint(
          '[Settings] Migrated legacy screen_config -> ${_keyForScreenId(id)}');
    } catch (e) {
      debugPrint('[Settings] Corrupted legacy screen_config dropped: $e');
    } finally {
      await prefs.remove(_legacyScreenConfigKey);
    }
  }

  /// Parse a "WxH" phone-frame spec; null for empty/"off"/malformed (B-042).
  static Size? _parsePhoneFrame(String? spec) {
    if (spec == null) return null;
    final s = spec.trim().toLowerCase();
    if (s.isEmpty || s == 'off' || s == 'none') return null;
    final parts = s.split('x');
    if (parts.length != 2) return null;
    final w = double.tryParse(parts[0].trim());
    final h = double.tryParse(parts[1].trim());
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return Size(w, h);
  }

  /// Set (or clear, when [size] is null) the debug phone frame (B-042).
  Future<void> setPhoneFrame(Size? size, {bool save = true}) async {
    phoneFrameNotifier.value = size;
    if (save) {
      final prefs = await SharedPreferences.getInstance();
      if (size == null) {
        await prefs.remove(_phoneFrameKey);
      } else {
        await prefs.setString(
            _phoneFrameKey, '${size.width.round()}x${size.height.round()}');
      }
    }
  }

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
      final useDarkIcons =
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.light;
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
  Future<void> setUseFilenameForMetadata(bool enable) => _saveBool(
      _useFilenameForMetadataKey, enable, useFilenameForMetadataNotifier);

  void toggleDebugLayout() =>
      debugLayoutNotifier.value = !debugLayoutNotifier.value;
}
