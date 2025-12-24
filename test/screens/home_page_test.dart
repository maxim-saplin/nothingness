import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/main.dart';
import 'package:nothingness/providers/audio_player_provider.dart';
import 'package:provider/provider.dart';

Widget createTestableApp() {
  final provider = AudioPlayerProvider();
  return ChangeNotifierProvider<AudioPlayerProvider>.value(
    value: provider,
    child: NothingApp(audioPlayerProvider: provider),
  );
}

void main() {
  group('HomePage', () {
    testWidgets('App renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableApp());

      // Verify library caret handle is present
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    });

    testWidgets('Media controls are rendered', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableApp());

      // Verify play button exists (play_arrow icon when paused)
      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);

      // Verify skip buttons exist
      expect(find.byIcon(Icons.skip_previous_rounded), findsWidgets);
      expect(find.byIcon(Icons.skip_next_rounded), findsWidgets);
    });

    testWidgets('Settings menu button exists', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableApp());

      // Verify three-dot menu button exists
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });
  });
}


