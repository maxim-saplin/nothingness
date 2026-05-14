import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/theme_id.dart';
import 'package:nothingness/providers/audio_player_provider.dart';
import 'package:nothingness/theme/themes.dart';
import 'package:nothingness/widgets/heroes/polo_hero.dart';
import 'package:provider/provider.dart';

Widget _buildPoloHero({required Brightness brightness}) {
  final provider = AudioPlayerProvider();
  return ChangeNotifierProvider<AudioPlayerProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: buildAppTheme(id: ThemeId.void_, brightness: brightness),
      home: const Scaffold(
        body: PoloHero(config: PoloScreenConfig()),
      ),
    ),
  );
}

void main() {
  group('PoloHero variant inversion', () {
    testWidgets('light variant wraps the body in a ColorFiltered ancestor', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPoloHero(brightness: Brightness.light));
      await tester.pump();

      expect(find.byType(ColorFiltered), findsOneWidget);
    });

    testWidgets('dark variant does not wrap the body in a ColorFiltered', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPoloHero(brightness: Brightness.dark));
      await tester.pump();

      expect(find.byType(ColorFiltered), findsNothing);
    });
  });
}
