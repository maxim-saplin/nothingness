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
      expect(service.uiScaleNotifier.value, SettingsService.defaultUiScale);
    });

    test('saveSettings persists data correctly', () async {
      const newSettings = SpectrumSettings(
        noiseGateDb: -50.0,
        barCount: BarCount.bars24,
        colorScheme: SpectrumColorScheme.purple,
      );

      await service.saveSettings(newSettings);
      await service.saveUiScale(2.0);

      // Verify persistence by reading from SharedPreferences directly
      final prefs = await SharedPreferences.getInstance();
      
      // Check Spectrum Settings
      final jsonString = prefs.getString('spectrum_settings');
      expect(jsonString, isNotNull);
      final json = jsonDecode(jsonString!);
      expect(json['noiseGateDb'], -50.0);
      expect(json['barCount'], 24);
      expect(json['colorScheme'], 'purple');

      // Check UI Scale
      final uiScale = prefs.getDouble('ui_scale');
      expect(uiScale, 2.0);
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
        'ui_scale': 1.5,
      });

      final settings = await service.loadSettings();

      expect(settings.noiseGateDb, -10.0);
      expect(settings.barCount, BarCount.bars8);
      expect(settings.colorScheme, SpectrumColorScheme.cyan);
      expect(settings.barStyle, BarStyle.glow);
      expect(settings.decaySpeed, DecaySpeed.slow);
      expect(service.uiScaleNotifier.value, 1.5);
    });

    test('loadSettings migrates legacy uiScale', () async {
      final legacyData = {
        'uiScale': 2.5,
      };

      SharedPreferences.setMockInitialValues({
        'spectrum_settings': jsonEncode(legacyData),
      });

      await service.loadSettings();

      expect(service.uiScaleNotifier.value, 2.5);
    });

    test('calculateSmartScaleForWidth returns correct scale factors', () {
      // Width 300 (phone) -> should be clamped to 1.0
      expect(service.calculateSmartScaleForWidth(300), 1.0);

      // Width 600 (standard target) -> should be 1.0
      expect(service.calculateSmartScaleForWidth(600), 1.0);

      // Width 1200 (wide screen) -> should be 2.0
      expect(service.calculateSmartScaleForWidth(1200), 2.0);

      // Width 2400 (very wide) -> should be clamped to 3.0
      expect(service.calculateSmartScaleForWidth(2400), 3.0);
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
