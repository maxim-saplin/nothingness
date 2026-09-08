import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/theme/palettes/void_dark.dart';
import 'package:nothingness/theme/palettes/void_light.dart';
import 'package:nothingness/widgets/heroes/cassette/cassette_image_variant.dart';
import 'package:nothingness/widgets/heroes/cassette/cassette_shared.dart';

void main() {
  test('formats the cassette label as artist then song', () {
    expect(
      formatCassetteLabel(artist: 'Test Artist', title: 'A Song'),
      'Test Artist - A Song',
    );
    expect(formatCassetteLabel(title: 'A Song'), 'A Song');
    expect(formatCassetteLabel(artist: 'Test Artist'), 'Test Artist');
    expect(formatCassetteLabel(), 'NO TAPE LOADED');
  });

  testWidgets('renders every high-fidelity cassette look from bundled layers', (
    tester,
  ) async {
    final context = CassetteVariantContext(
      config: const CassetteScreenConfig(),
      title: 'A Carefully Named Mixtape',
      artist: 'Test Artist',
      isPlaying: false,
      positionMs: 35 * 1000,
      durationMs: 100 * 1000,
      onPlayPause: () {},
      onPrevious: () {},
      onNext: () {},
      onSeek: (_) {},
      haptics: const CassetteHaptics(enabled: false),
    );

    for (final palette in [voidPaletteLight, voidPaletteDark]) {
      for (final look in CassetteLook.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: [palette]),
            home: Center(
              child: SizedBox(
                width: 418,
                height: 257,
                child: CassetteImageVariant(
                  context,
                  look: look,
                  vertical: false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(CassetteImageVariant), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
