import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';

import 'package:nothingness/models/spectrum_settings.dart';

void main() {
  group('ScreenConfig', () {
    group('SpectrumScreenConfig', () {
      test('toJson serializes correctly', () {
        const config = SpectrumScreenConfig(
          showMediaControls: false,
          textScale: 1.5,
          spectrumWidthFactor: 0.8,
          spectrumHeightFactor: 0.9,
          mediaControlScale: 1.2,
          mediaControlColorScheme: SpectrumColorScheme.cyan,
          textColorScheme: SpectrumColorScheme.purple,
        );
        final json = config.toJson();

        expect(json['type'], 'spectrum');
        expect(json['name'], 'Spectrum');
        expect(json['showMediaControls'], false);
        expect(json['textScale'], 1.5);
        expect(json['spectrumWidthFactor'], 0.8);
        expect(json['spectrumHeightFactor'], 0.9);
        expect(json['mediaControlScale'], 1.2);
        expect(json['mediaControlColorScheme'], 'cyan');
        expect(json['textColorScheme'], 'purple');
      });

      test('fromJson deserializes correctly', () {
        final json = {
          'type': 'spectrum',
          'name': 'Spectrum',
          'showMediaControls': false,
          'textScale': 1.2,
          'spectrumWidthFactor': 0.7,
          'spectrumHeightFactor': 0.6,
          'mediaControlScale': 0.5,
          'mediaControlColorScheme': 'cyan',
          'textColorScheme': 'purple',
        };
        final config = ScreenConfig.fromJson(json) as SpectrumScreenConfig;

        expect(config.type, ScreenType.spectrum);
        expect(config.showMediaControls, false);
        expect(config.textScale, 1.2);
        expect(config.spectrumWidthFactor, 0.7);
        expect(config.spectrumHeightFactor, 0.6);
        expect(config.mediaControlScale, 0.5);
        expect(config.mediaControlColorScheme, SpectrumColorScheme.cyan);
        expect(config.textColorScheme, SpectrumColorScheme.purple);
      });

      test('fromJson uses defaults when fields are missing', () {
        final json = {'type': 'spectrum'};
        final config = ScreenConfig.fromJson(json) as SpectrumScreenConfig;

        expect(config.showMediaControls, true);
        expect(config.textScale, 1.0);
        expect(config.spectrumWidthFactor, 1.0);
        expect(config.spectrumHeightFactor, 1.0);
        expect(config.mediaControlScale, 1.0);
        expect(config.mediaControlColorScheme, SpectrumColorScheme.classic);
        expect(config.textColorScheme, SpectrumColorScheme.classic);
      });
    });

    group('DotScreenConfig', () {
      test('toJson serializes correctly', () {
        const config = DotScreenConfig(
          minDotSize: 30.0,
          maxDotSize: 150.0,
          dotOpacity: 0.8,
          textOpacity: 0.5,
          sensitivity: 3.0,
        );
        final json = config.toJson();

        expect(json['type'], 'dot');
        expect(json['name'], 'Dot');
        expect(json['minDotSize'], 30.0);
        expect(json['maxDotSize'], 150.0);
        expect(json['dotOpacity'], 0.8);
        expect(json['textOpacity'], 0.5);
        expect(json['sensitivity'], 3.0);
      });

      test('fromJson deserializes correctly', () {
        final json = {
          'type': 'dot',
          'minDotSize': 25.0,
          'maxDotSize': 100.0,
          'dotOpacity': 0.9,
          'textOpacity': 0.7,
          'sensitivity': 1.5,
        };
        final config = ScreenConfig.fromJson(json) as DotScreenConfig;

        expect(config.type, ScreenType.dot);
        expect(config.minDotSize, 25.0);
        expect(config.maxDotSize, 100.0);
        expect(config.dotOpacity, 0.9);
        expect(config.textOpacity, 0.7);
        expect(config.sensitivity, 1.5);
      });

      test('fromJson uses defaults when fields are missing', () {
        final json = {'type': 'dot'};
        final config = ScreenConfig.fromJson(json) as DotScreenConfig;

        expect(config.minDotSize, 20.0);
        expect(config.maxDotSize, 120.0);
        expect(config.dotOpacity, 1.0);
        expect(config.textOpacity, 1.0);
        expect(config.sensitivity, 2.0);
      });
    });

    group('PoloScreenConfig', () {
      test('toJson serializes but EXCLUDES lcdRect', () {
        final config = PoloScreenConfig(
          backgroundImagePath: 'assets/custom.png',
          fontFamily: 'CustomFont',
          lcdRect: const Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
          textColor: const Color(0xFF112233),
        );

        final json = config.toJson();

        expect(json['type'], 'polo');
        expect(json['name'], 'Polo');
        expect(json['backgroundImagePath'], 'assets/custom.png');
        expect(json['fontFamily'], 'CustomFont');
        expect(json['textColor'], 0xFF112233);

        // Critical: lcdRect should NOT be in the JSON
        expect(json.containsKey('lcdRect'), isFalse);
      });

      test('fromJson uses code defaults for lcdRect (ignoring any saved data)', () {
        // Even if JSON somehow contains lcdRect (legacy data or manual edit),
        // it should be ignored in favor of the constructor defaults.
        final json = {
          'type': 'polo',
          'name': 'Polo',
          'backgroundImagePath': 'assets/saved.png',
          'fontFamily': 'SavedFont',
          'textColor': 0xFF998877,
          // Fake lcdRect data that should be ignored
          'lcdRect': [0.9, 0.9, 0.1, 0.1],
        };

        final config = ScreenConfig.fromJson(json) as PoloScreenConfig;

        expect(config.type, ScreenType.polo);
        expect(config.backgroundImagePath, 'assets/saved.png');
        expect(config.fontFamily, 'SavedFont');
        expect(config.textColor.toARGB32(), 0xFF998877);

        // Verify it uses the DEFAULT rect from the constructor, not the JSON or empty
        // We can't easily check the exact default values without hardcoding them here
        // or exposing constants, but we can verify it's NOT the 0.9,0.9 rect we passed.
        // And it should match a new instance's default.
        final defaultConfig = PoloScreenConfig();
        expect(config.lcdRect, defaultConfig.lcdRect);

        expect(config.lcdRect.left, isNot(0.9));
      });

      test('fromJson handles missing optional fields', () {
        final json = {'type': 'polo'};

        final config = ScreenConfig.fromJson(json) as PoloScreenConfig;

        expect(config.backgroundImagePath, 'assets/images/polo.png');
        expect(config.fontFamily, 'Press Start 2P');
        expect(config.textColor, const Color(0xFF000000));
      });
    });

    test('ScreenConfig.fromJson defaults to Spectrum for unknown types', () {
      final json = {'type': 'unknown_future_screen'};
      final config = ScreenConfig.fromJson(json);

      expect(config, isA<SpectrumScreenConfig>());
    });
  });
}
