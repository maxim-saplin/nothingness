import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/main.dart';

void main() {
  group('HomePage', () {
    testWidgets('App renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(const NothingApp());

      // Verify app renders (on macOS preview mode)
      expect(find.text('macOS Preview'), findsOneWidget);
    });

    testWidgets('Media controls are rendered', (WidgetTester tester) async {
      await tester.pumpWidget(const NothingApp());

      // Verify play button exists (play_arrow icon when paused)
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      
      // Verify skip buttons exist
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });

    testWidgets('Settings menu button exists', (WidgetTester tester) async {
      await tester.pumpWidget(const NothingApp());

      // Verify three-dot menu button exists
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });
  });
}

