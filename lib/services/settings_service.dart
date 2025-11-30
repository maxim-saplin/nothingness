import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/spectrum_settings.dart';

class SettingsService {
  // Singleton
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _settingsKey = 'spectrum_settings';
  static const String _uiScaleKey = 'ui_scale';

  // --- APP DEFAULTS (Single Source of Truth) ---
  static const double defaultNoiseGateDb = -35.0;
  static const BarCount defaultBarCount = BarCount.bars12;
  static const SpectrumColorScheme defaultColorScheme =
      SpectrumColorScheme.classic;
  static const BarStyle defaultBarStyle = BarStyle.segmented;
  static const DecaySpeed defaultDecaySpeed = DecaySpeed.medium;
  static const double defaultUiScale = -1.0; // -1.0 indicates "auto" / not set

  final ValueNotifier<SpectrumSettings> settingsNotifier = ValueNotifier(
    const SpectrumSettings(),
  );

  final ValueNotifier<double> uiScaleNotifier = ValueNotifier(defaultUiScale);

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

    // Determine target width based on screen characteristics.
    //
    // Heuristic:
    // - Low DPI (< 2.0) AND width in automotive range (1600-2100 logical) = Automotive
    //   Use 850 target for large touch targets (e.g. Zeekr 1920 -> 2.25x)
    // - Otherwise = Tablet/Normal display
    //   Use 960 target for balanced information density
    //
    // Automotive displays are typically 1920x720 or 1920x1080 at ~160dpi (DPR ~1.0).
    // Very wide low-DPI screens (> 2100) are likely large tablets, not cars.
    final bool isAutomotive =
        devicePixelRatio < 2.0 && logicalWidth >= 1600 && logicalWidth <= 2100;
    final double targetWidth = isAutomotive ? 850.0 : 960.0;

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

    return settings;
  }

  /// Saves the spectrum settings to persistence.
  Future<void> saveSettings(SpectrumSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    settingsNotifier.value = settings;
  }

  /// Saves the UI scale to persistence.
  Future<void> saveUiScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiScaleKey, scale);
    uiScaleNotifier.value = scale;
  }
}
