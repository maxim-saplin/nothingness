import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/theme_id.dart';
import 'package:nothingness/theme/themes.dart';
import 'package:nothingness/widgets/media_button.dart';

/// B-012: MediaButton should provide a touch-down opacity dip so taps have
/// immediate visual feedback rather than waiting on the upstream state flip.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: buildAppTheme(id: ThemeId.void_, brightness: Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    );
  }

  Finder dimFinder() => find.byKey(MediaButton.touchDownDimKey);

  double? currentOpacity(WidgetTester tester) {
    final w = tester.widget<AnimatedOpacity>(dimFinder());
    return w.opacity;
  }

  testWidgets('exposes an AnimatedOpacity tagged with touchDownDimKey',
      (tester) async {
    await tester.pumpWidget(
      host(MediaButton(
        icon: Icons.play_arrow_rounded,
        size: 48,
        onTap: () {},
      )),
    );
    expect(dimFinder(), findsOneWidget);
  });

  testWidgets('idle opacity is 1.0; drops below 1.0 on touch-down; restores '
      'on release',
      (tester) async {
    await tester.pumpWidget(
      host(MediaButton(
        icon: Icons.play_arrow_rounded,
        size: 48,
        onTap: () {},
      )),
    );

    // Idle: full opacity.
    expect(currentOpacity(tester), 1.0);

    // Touch down (do NOT release) — opacity should drop.
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(MediaButton)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentOpacity(tester), lessThan(1.0));

    // Release — opacity restores.
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentOpacity(tester), 1.0);
  });

  testWidgets('cancel restores opacity', (tester) async {
    await tester.pumpWidget(
      host(MediaButton(
        icon: Icons.play_arrow_rounded,
        size: 48,
        onTap: () {},
      )),
    );

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(MediaButton)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentOpacity(tester), lessThan(1.0));
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentOpacity(tester), 1.0);
  });

  testWidgets('invokes onTap on release', (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      host(MediaButton(
        icon: Icons.play_arrow_rounded,
        size: 48,
        onTap: () => taps++,
      )),
    );
    await tester.tap(find.byType(MediaButton));
    expect(taps, 1);
  });
}
