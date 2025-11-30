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

  /// Calculates a smart UI scale based purely on logical width.
  /// Target logical width is ~600dp for automotive/tablet interfaces.
  double calculateSmartScaleForWidth(double logicalWidth) {
    // Guard against invalid width; fall back to no scaling.
    if (logicalWidth <= 0) {
      return 1.0;
    }

    // Base target width for a \"standard\" readable interface
    const double targetWidth = 600.0;

    // Calculate scale
    final double scale = logicalWidth / targetWidth;

    // Clamp values:
    // - Min 1.0: Don't shrink UI on phones (width < 600)
    // - Max 3.0: Don't let it get absurdly huge on 4K screens
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
      uiScaleNotifier.value = prefs.getDouble(_uiScaleKey) ?? defaultUiScale;
    } else {
      // Migration: Check if it was in the old JSON
      if (jsonString != null) {
        try {
          final json = jsonDecode(jsonString);
          final oldScale =
              (json['uiScale'] as num?)?.toDouble() ??
              (json['textScale'] as num?)?.toDouble();

          if (oldScale != null) {
            uiScaleNotifier.value = oldScale;
            // Persist to new key immediately
            await prefs.setDouble(_uiScaleKey, oldScale);
          } else {
            uiScaleNotifier.value = defaultUiScale;
          }
        } catch (_) {
          uiScaleNotifier.value = defaultUiScale;
        }
      } else {
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
