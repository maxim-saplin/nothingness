import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';

void main() {
  group('ScreenConfig', () {
    group('SpectrumScreenConfig', () {
      test('toJson serializes correctly', () {
        const config = SpectrumScreenConfig();
        final json = config.toJson();

        expect(json['type'], 'spectrum');
        expect(json['name'], 'Spectrum');
      });

      test('fromJson deserializes correctly', () {
        final json = {'type': 'spectrum', 'name': 'Spectrum'};
        final config = ScreenConfig.fromJson(json);

        expect(config, isA<SpectrumScreenConfig>());
        expect(config.type, ScreenType.spectrum);
        expect(config.name, 'Spectrum');
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
