import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/widgets/press_feedback.dart';

/// B-030: PressFeedback wraps any tappable child and dips its opacity on
/// touch-down so the user gets immediate visual confirmation of their tap.
/// Calibrated for real-hardware visibility (the previous MediaButton
/// constants were too subtle on a phone).
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  double currentOpacity(WidgetTester tester) {
    final w = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(PressFeedback),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    return w.opacity;
  }

  testWidgets('idle opacity is 1.0', (tester) async {
    await tester.pumpWidget(host(
      PressFeedback(
        onTap: () {},
        child: const SizedBox(width: 100, height: 40),
      ),
    ));
    expect(currentOpacity(tester), 1.0);
  });

  testWidgets('touch-down drops opacity to PressFeedback.pressedOpacity',
      (tester) async {
    await tester.pumpWidget(host(
      PressFeedback(
        onTap: () {},
        child: const SizedBox(width: 100, height: 40),
      ),
    ));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressFeedback)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentOpacity(tester), PressFeedback.pressedOpacity);
    // Release so the gesture object doesn't leak into the next test.
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('release restores opacity to 1.0', (tester) async {
    await tester.pumpWidget(host(
      PressFeedback(
        onTap: () {},
        child: const SizedBox(width: 100, height: 40),
      ),
    ));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressFeedback)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentOpacity(tester), PressFeedback.pressedOpacity);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentOpacity(tester), 1.0);
  });

  testWidgets('cancel restores opacity to 1.0', (tester) async {
    await tester.pumpWidget(host(
      PressFeedback(
        onTap: () {},
        child: const SizedBox(width: 100, height: 40),
      ),
    ));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressFeedback)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentOpacity(tester), PressFeedback.pressedOpacity);
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentOpacity(tester), 1.0);
  });

  testWidgets('onTap callback fires on tap', (tester) async {
    int taps = 0;
    await tester.pumpWidget(host(
      PressFeedback(
        onTap: () => taps++,
        child: const SizedBox(width: 100, height: 40),
      ),
    ));
    await tester.tap(find.byType(PressFeedback));
    expect(taps, 1);
  });

  testWidgets('long-press start + end pass through', (tester) async {
    bool started = false;
    bool ended = false;
    bool pressed = false;
    await tester.pumpWidget(host(
      PressFeedback(
        onTap: () {},
        onLongPress: () => pressed = true,
        onLongPressStart: (_) => started = true,
        onLongPressEnd: (_) => ended = true,
        child: const SizedBox(width: 100, height: 40),
      ),
    ));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressFeedback)));
    // Hold past the long-press threshold then release.
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(started, isTrue, reason: 'onLongPressStart must pass through');
    expect(ended, isTrue, reason: 'onLongPressEnd must pass through');
    expect(pressed, isTrue, reason: 'onLongPress must pass through');
  });

  test('calibration constants match B-030 spec', () {
    expect(PressFeedback.pressedOpacity, 0.4);
    expect(PressFeedback.fadeInDuration, const Duration(milliseconds: 120));
    expect(PressFeedback.fadeOutDuration, const Duration(milliseconds: 200));
  });
}
