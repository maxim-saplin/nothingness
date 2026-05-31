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

      // Mock the app media method channel used by PlatformChannels so settings
      // pushes (best-effort) don't throw MissingPluginException in unit tests.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.saplin.nothingness/media'),
            (MethodCall methodCall) async => null,
          );
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

    test('saveScreenConfig persists screen selection under per-screen key',
        () async {
      final config = PoloScreenConfig();
      await service.saveScreenConfig(config);

      final prefs = await SharedPreferences.getInstance();
      // B-028: per-screen key replaces the single composite blob.
      final jsonString = prefs.getString('screen_config_polo');

      expect(jsonString, isNotNull);
      final json = jsonDecode(jsonString!);
      expect(json['type'], 'polo');
      expect(json['name'], 'Polo');
      // Active-screen marker tracks which skin to boot into.
      expect(prefs.getString('active_screen_id'), 'polo');
      // Legacy composite key is NOT written.
      expect(prefs.getString('screen_config'), isNull);
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

      // --- Automotive – Zeekr DHU (2560 logical, DPR 1.0) ---
      // 2560/800 = 3.2, clamped to 3.0
      expect(
        service.calculateSmartScaleForWidth(2560, devicePixelRatio: 1.0),
        3.0,
      );

      // --- Tablets (High DPI OR outside automotive range) - Target 960 ---

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

    test('isLikelyAutomotive detects automotive vs phone displays', () {
      // Zeekr DHU: 2560 logical, DPR 1.0
      expect(SettingsService.isLikelyAutomotive(2560, 1.0), isTrue);
      // Typical IVI: 1920 logical, DPR 1.0
      expect(SettingsService.isLikelyAutomotive(1920, 1.0), isTrue);
      // Phone: 1080 logical, DPR 2.75
      expect(SettingsService.isLikelyAutomotive(1080, 2.75), isFalse);
      // Tablet at high DPI
      expect(SettingsService.isLikelyAutomotive(1920, 2.0), isFalse);
      // Small low-DPI display (not wide enough)
      expect(SettingsService.isLikelyAutomotive(1280, 1.0), isFalse);
    });

    test('loadSettings handles corrupted data by returning defaults', () async {
      SharedPreferences.setMockInitialValues({
        'spectrum_settings': '{ invalid json }',
      });

      final settings = await service.loadSettings();

      expect(settings.noiseGateDb, SettingsService.defaultNoiseGateDb);
    });
  });

  // ---------------------------------------------------------------------------
  // B-028: per-screen `screen_config_<id>` keys. Replaces the single
  // `screen_config` blob, which caused cross-skin cycles to clobber
  // per-skin fields (e.g. DotScreenConfig.showSongInfo from B-020).
  // ---------------------------------------------------------------------------
  group('B-028 per-screen screen_config persistence', () {
    late SettingsService service;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      service = SettingsService();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.saplin.nothingness/media'),
        (MethodCall _) async => null,
      );
    });

    test('saveScreenConfig writes to per-screen key (not legacy)', () async {
      const dot = DotScreenConfig(showSongInfo: true);
      await service.saveScreenConfig(dot);

      final prefs = await SharedPreferences.getInstance();
      // New per-screen key holds the blob.
      final raw = prefs.getString('screen_config_dot');
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['type'], 'dot');
      expect(json['showSongInfo'], isTrue);

      // The legacy composite key is NOT written by saveScreenConfig.
      expect(prefs.getString('screen_config'), isNull);
    });

    test('loadScreenConfig returns the matching per-screen blob', () async {
      const dot = DotScreenConfig(showSongInfo: true);
      await service.saveScreenConfig(dot);

      final loaded = await service.loadScreenConfig('dot');
      expect(loaded, isA<DotScreenConfig>());
      expect((loaded as DotScreenConfig).showSongInfo, isTrue);
    });

    test('cross-skin cycle preserves per-skin fields (the B-028 symptom)',
        () async {
      // Save Dot with a non-default field.
      const dot = DotScreenConfig(showSongInfo: true);
      await service.saveScreenConfig(dot);

      // Save Spectrum on top — this used to overwrite the shared
      // `screen_config` blob and lose the Dot field.
      const spectrum = SpectrumScreenConfig();
      await service.saveScreenConfig(spectrum);

      // Re-read Dot's persisted config; the non-default must still be there.
      final reloaded = await service.loadScreenConfig('dot');
      expect(reloaded, isA<DotScreenConfig>());
      expect((reloaded as DotScreenConfig).showSongInfo, isTrue);
    });

    test('loadScreenConfig with no persisted blob returns null', () async {
      final loaded = await service.loadScreenConfig('dot');
      expect(loaded, isNull);
    });

    test('migration: legacy `screen_config` is moved to per-screen key',
        () async {
      const dot = DotScreenConfig(showSongInfo: true, maxDotSize: 200);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'screen_config': jsonEncode(dot.toJson()),
      });

      // First read after upgrade triggers the one-shot migration.
      final loaded = await service.loadScreenConfig('dot');
      expect(loaded, isA<DotScreenConfig>());
      expect((loaded as DotScreenConfig).showSongInfo, isTrue);
      expect(loaded.maxDotSize, 200);

      final prefs = await SharedPreferences.getInstance();
      // Legacy key is gone.
      expect(prefs.getString('screen_config'), isNull);
      // Migrated blob lives under the per-screen key now.
      final migrated = prefs.getString('screen_config_dot');
      expect(migrated, isNotNull);
      final json = jsonDecode(migrated!) as Map<String, dynamic>;
      expect(json['type'], 'dot');
      expect(json['showSongInfo'], isTrue);
    });

    test('migration: corrupted legacy blob is silently dropped', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'screen_config': 'not json',
      });

      // Must not crash.
      final loaded = await service.loadScreenConfig('dot');
      expect(loaded, isNull);

      final prefs = await SharedPreferences.getInstance();
      // Corrupted legacy key removed so we don't retry on every load.
      expect(prefs.getString('screen_config'), isNull);

      // Subsequent saves still work normally.
      const dot = DotScreenConfig(showSongInfo: true);
      await service.saveScreenConfig(dot);
      expect(prefs.getString('screen_config_dot'), isNotNull);
    });

    test('migration is idempotent across multiple calls', () async {
      const dot = DotScreenConfig(showSongInfo: true);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'screen_config': jsonEncode(dot.toJson()),
      });

      final first = await service.loadScreenConfig('dot');
      final second = await service.loadScreenConfig('dot');
      expect(first, isA<DotScreenConfig>());
      expect(second, isA<DotScreenConfig>());
      expect((first! as DotScreenConfig).showSongInfo, isTrue);
      expect((second! as DotScreenConfig).showSongInfo, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('screen_config'), isNull);
    });

    test('void key uses the `void` suffix (not `void_`)', () async {
      const voidCfg = VoidScreenConfig();
      await service.saveScreenConfig(voidCfg);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('screen_config_void'), isNotNull);
      expect(prefs.getString('screen_config_void_'), isNull);

      final loaded = await service.loadScreenConfig('void');
      expect(loaded, isA<VoidScreenConfig>());
    });
  });
}
