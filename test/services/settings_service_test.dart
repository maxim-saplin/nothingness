import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsService', () {
    late SettingsService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = SettingsService();
    });

    test('loadSettings returns defaults when no data is saved', () async {
      final settings = await service.loadSettings();

      expect(settings.noiseGateDb, SettingsService.defaultNoiseGateDb);
      expect(settings.barCount, SettingsService.defaultBarCount);
      expect(settings.colorScheme, SettingsService.defaultColorScheme);
    });

    test('saveSettings persists data correctly', () async {
      const newSettings = SpectrumSettings(
        noiseGateDb: -50.0,
        barCount: BarCount.bars24,
        colorScheme: SpectrumColorScheme.purple,
      );

      await service.saveSettings(newSettings);

      // Verify persistence by reading from SharedPreferences directly
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('spectrum_settings');
      expect(jsonString, isNotNull);
      
      final json = jsonDecode(jsonString!);
      expect(json['noiseGateDb'], -50.0);
      expect(json['barCount'], 24);
      expect(json['colorScheme'], 'purple');
    });

    test('loadSettings retrieves saved data', () async {
      final savedData = {
        'noiseGateDb': -10.0,
        'barCount': 8,
        'colorScheme': 'cyan',
        'barStyle': 'glow',
        'decaySpeed': 0.05, // Slow
      };

      SharedPreferences.setMockInitialValues({
        'spectrum_settings': jsonEncode(savedData),
      });

      final settings = await service.loadSettings();

      expect(settings.noiseGateDb, -10.0);
      expect(settings.barCount, BarCount.bars8);
      expect(settings.colorScheme, SpectrumColorScheme.cyan);
      expect(settings.barStyle, BarStyle.glow);
      expect(settings.decaySpeed, DecaySpeed.slow);
    });

    test('loadSettings handles corrupted data by returning defaults', () async {
      SharedPreferences.setMockInitialValues({
        'spectrum_settings': '{ invalid json }',
      });

      final settings = await service.loadSettings();

      expect(settings.noiseGateDb, SettingsService.defaultNoiseGateDb);
    });
  });
}

