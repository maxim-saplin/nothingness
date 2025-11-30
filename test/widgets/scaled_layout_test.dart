import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:nothingness/widgets/scaled_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScaledLayout', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // Reset singleton for each test
      // Note: Since SettingsService is a singleton, we need to be careful.
      // The tests below will set the value directly on the notifier.
    });

    testWidgets('renders child without scaling when uiScale is 1.0', (
      WidgetTester tester,
    ) async {
      SettingsService().uiScaleNotifier.value = 1.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: ScaledLayout(
            child: SizedBox(width: 100, height: 100, child: Text('Test')),
          ),
        ),
      );

      // Should find the text
      expect(find.text('Test'), findsOneWidget);

      // Should NOT find a Transform with scale != 1.0
      final transformFinder = find.byType(Transform);
      if (transformFinder.evaluate().isNotEmpty) {
        final transform = tester.widget<Transform>(transformFinder.first);
        final matrix = transform.transform;
        expect(matrix.getMaxScaleOnAxis(), 1.0);
      }
    });

    testWidgets('applies scaling when uiScale is set', (
      WidgetTester tester,
    ) async {
      const double scale = 2.0;
      SettingsService().uiScaleNotifier.value = scale;

      await tester.pumpWidget(
        const MaterialApp(
          home: ScaledLayout(
            child: SizedBox(width: 100, height: 100, child: Text('Scaled')),
          ),
        ),
      );

      // Should find the text
      expect(find.text('Scaled'), findsOneWidget);

      // Should find a Transform widget
      expect(find.byType(Transform), findsOneWidget);

      // Verify the scale factor
      final transform = tester.widget<Transform>(find.byType(Transform));
      final matrix = transform.transform;
      // Check diagonal elements for scale (indices 0 and 5 in 4x4 matrix column-major)
      expect(matrix.storage[0], scale); // Scale X
      expect(matrix.storage[5], scale); // Scale Y
    });

    testWidgets('handles invalid scale by falling back to 1.0', (
      WidgetTester tester,
    ) async {
      SettingsService().uiScaleNotifier.value = 0.0; // Invalid

      await tester.pumpWidget(
        const MaterialApp(home: ScaledLayout(child: Text('Fallback'))),
      );

      expect(find.text('Fallback'), findsOneWidget);

      // Should effectively be 1.0, so no transform or transform with scale 1.0
      // Implementation might skip Transform widget if scale is ~1.0
      final transformFinder = find.byType(Transform);
      if (transformFinder.evaluate().isNotEmpty) {
        final transform = tester.widget<Transform>(transformFinder.first);
        expect(transform.transform.getMaxScaleOnAxis(), 1.0);
      }
    });
  });
}
