import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock the SystemChrome method channel to avoid platform errors in tests
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async => null,
      );

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

    test('saveScreenConfig persists screen selection', () async {
      final config = PoloScreenConfig();
      await service.saveScreenConfig(config);

      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('screen_config');

      expect(jsonString, isNotNull);
      final json = jsonDecode(jsonString!);
      expect(json['type'], 'polo');
      expect(json['name'], 'Polo');
    });

    test('loadSettings retrieves saved data', () async {
      final savedData = {
        'noiseGateDb': -10.0,
        'barCount': 8,
        'colorScheme': 'cyan',
        'barStyle': 'glow',
        'decaySpeed': 0.05, // Slow
      };

      final savedScreenConfig = {
        'type': 'polo',
        'name': 'Polo',
        'fontFamily': 'TestFont',
      };

      SharedPreferences.setMockInitialValues({
        'spectrum_settings': jsonEncode(savedData),
        'ui_scale': 1.5,
        'screen_config': jsonEncode(savedScreenConfig),
      });

      final settings = await service.loadSettings();

      expect(settings.noiseGateDb, -10.0);
      expect(settings.barCount, BarCount.bars8);
      expect(settings.colorScheme, SpectrumColorScheme.cyan);
      expect(settings.barStyle, BarStyle.glow);
      expect(settings.decaySpeed, DecaySpeed.slow);

      expect(service.uiScaleNotifier.value, 1.5);

      final loadedConfig = service.screenConfigNotifier.value;
      expect(loadedConfig, isA<PoloScreenConfig>());
      expect((loadedConfig as PoloScreenConfig).fontFamily, 'TestFont');
    });

    test('loadSettings migrates legacy uiScale', () async {
      final legacyData = {'uiScale': 2.5};

      SharedPreferences.setMockInitialValues({
        'spectrum_settings': jsonEncode(legacyData),
      });

      await service.loadSettings();

      expect(service.uiScaleNotifier.value, 2.5);
    });

    test('calculateSmartScaleForWidth returns correct scale factors', () {
      // --- Automotive (Low DPI + width 1600-2100) - Target 800 ---

      // Width 1920 (Zeekr) at low DPI -> 1920/800 = 2.4
      expect(
        service.calculateSmartScaleForWidth(1920, devicePixelRatio: 1.0),
        closeTo(2.4, 0.01),
      );

      // Width 1600 (lower bound automotive) at low DPI -> 1600/800 = 2.0
      expect(
        service.calculateSmartScaleForWidth(1600, devicePixelRatio: 1.0),
        closeTo(2.0, 0.01),
      );

      // --- Tablets (High DPI OR outside automotive range) - Target 960 ---

      // Width 2560 (very wide low-DPI tablet, outside automotive range) -> 2560/960 = 2.66
      expect(
        service.calculateSmartScaleForWidth(2560, devicePixelRatio: 1.0),
        closeTo(2.66, 0.01),
      );

      // Width 1280 (tablet) at low DPI but below automotive range -> 1280/960 = 1.33
      expect(
        service.calculateSmartScaleForWidth(1280, devicePixelRatio: 1.0),
        closeTo(1.33, 0.01),
      );

      // Width 600 (phone/small tablet) at high DPI -> clamped to 1.0
      expect(
        service.calculateSmartScaleForWidth(600, devicePixelRatio: 2.0),
        1.0,
      );

      // Width 960 (standard target) at high DPI -> 1.0
      expect(
        service.calculateSmartScaleForWidth(960, devicePixelRatio: 2.0),
        1.0,
      );

      // Width 1280 (common tablet) at high DPI -> 1280/960 = 1.33
      expect(
        service.calculateSmartScaleForWidth(1280, devicePixelRatio: 2.0),
        closeTo(1.33, 0.01),
      );

      // Width 1920 (wide tablet) at high DPI -> uses tablet target 960 -> 1920/960 = 2.0
      expect(
        service.calculateSmartScaleForWidth(1920, devicePixelRatio: 2.0),
        2.0,
      );
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
