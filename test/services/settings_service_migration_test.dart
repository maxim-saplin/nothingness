import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/operating_mode.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock the SystemChrome method channel so SystemChrome.* calls don't blow up.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall methodCall) async => null,
  );

  group('SettingsService migration: audioSource -> operatingMode', () {
    late SettingsService service;

    setUp(() {
      service = SettingsService();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.saplin.nothingness/media'),
        (MethodCall methodCall) async => null,
      );
    });

    test('microphone -> background, then idempotent on second load', () async {
      SharedPreferences.setMockInitialValues({
        'spectrum_settings': jsonEncode(<String, Object?>{
          'noiseGateDb': -35.0,
          'barCount': 24,
          'colorScheme': 'classic',
          'barStyle': 'segmented',
          'decaySpeed': 0.12,
          'audioSource': 'microphone',
        }),
      });

      await service.loadSettings();
      expect(service.operatingModeNotifier.value, OperatingMode.background);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('operating_mode'), 'background');

      // Legacy field has been stripped from the persisted spectrum_settings.
      final after = jsonDecode(prefs.getString('spectrum_settings')!)
          as Map<String, dynamic>;
      expect(after.containsKey('audioSource'), isFalse);

      // Second load must not duplicate work — the value already exists, so
      // the migration branch is skipped entirely.
      await service.loadSettings();
      expect(service.operatingModeNotifier.value, OperatingMode.background);
      expect(prefs.getString('operating_mode'), 'background');
    });

    test('player -> own', () async {
      SharedPreferences.setMockInitialValues({
        'spectrum_settings': jsonEncode(<String, Object?>{
          'audioSource': 'player',
        }),
      });

      await service.loadSettings();
      expect(service.operatingModeNotifier.value, OperatingMode.own);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('operating_mode'), 'own');
    });

    test('no legacy field present -> defaults to own and writes key',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await service.loadSettings();
      expect(service.operatingModeNotifier.value, OperatingMode.own);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('operating_mode'), 'own');
    });
  });
}
