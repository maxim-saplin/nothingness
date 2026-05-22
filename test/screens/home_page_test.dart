import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/main.dart';
import 'package:nothingness/providers/audio_player_provider.dart';
import 'package:nothingness/widgets/transport_row.dart';
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
      // The void chrome surfaces a settings glyph (⋮) in the top-right.
      expect(find.byKey(const ValueKey('void-settings-button')), findsOneWidget);
    });

    testWidgets('Transport row exposes prev / play / next buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestableApp());
      await tester.pump();

      expect(find.byType(TransportRow), findsOneWidget);
      expect(find.byKey(TransportRow.prevKey), findsOneWidget);
      expect(find.byKey(TransportRow.playKey), findsOneWidget);
      expect(find.byKey(TransportRow.nextKey), findsOneWidget);
    });
  });
}
