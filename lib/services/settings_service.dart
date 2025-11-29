import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/spectrum_settings.dart';

class SettingsService {
  // Singleton
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _settingsKey = 'spectrum_settings';

  // --- APP DEFAULTS (Single Source of Truth) ---
  static const double defaultNoiseGateDb = -35.0;
  static const BarCount defaultBarCount = BarCount.bars12;
  static const SpectrumColorScheme defaultColorScheme = SpectrumColorScheme.classic;
  static const BarStyle defaultBarStyle = BarStyle.segmented;
  static const DecaySpeed defaultDecaySpeed = DecaySpeed.medium;

  /// Loads settings from persistence, or returns defaults if none exist.
  Future<SpectrumSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_settingsKey);
    
    if (jsonString != null) {
      try {
        return SpectrumSettings.fromJson(jsonDecode(jsonString));
      } catch (e) {
        // If parsing fails, fall back to defaults
        return const SpectrumSettings();
      }
    }
    
    // No saved settings found, return defaults
    return const SpectrumSettings();
  }

  /// Saves the current settings to persistence.
  Future<void> saveSettings(SpectrumSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}

