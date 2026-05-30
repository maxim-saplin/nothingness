import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/theme_id.dart';
import 'package:nothingness/theme/themes.dart';
import 'package:nothingness/widgets/hero_feedback_surface.dart';

/// B-012 — hero tap-ring + directional swipe-flash feedback. These tests
/// assert the overlays appear when expected and don't intercept the
/// underlying gestures.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: buildAppTheme(id: ThemeId.void_, brightness: Brightness.dark),
      home: Scaffold(body: child),
    );
  }

  group('tap ring', () {
    testWidgets('appears on tap-down and disappears after the animation',
        (tester) async {
      bool tapped = false;
      await tester.pumpWidget(host(
        SizedBox(
          width: 400,
          height: 400,
          child: HeroFeedbackSurface(
            onTap: () => tapped = true,
            onHorizontalDragUpdate: (_) {},
            onHorizontalDragEnd: (_) {},
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ));

      // Pre-tap: the ring slot widget isn't even mounted yet (the surface
      // only renders it once the first tap-down has happened).
      expect(find.byKey(HeroFeedbackSurface.tapRingKey), findsNothing);

      // Tap down — triggers a ring at the touch point. onTapDown fires
      // when the tap recognizer wins its arena; with no competing recognizers
      // and an unreleased pointer, that's after kPressTimeout ≈ 100 ms.
      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(HeroFeedbackSurface)));
      // Let kPressTimeout elapse so onTapDown fires; pump one more frame
      // so the spawn-ring setState is committed.
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 16));

      // Mid-animation a CustomPaint should be visible inside the ring slot.
      final ringSlot = find.byKey(HeroFeedbackSurface.tapRingKey);
      expect(ringSlot, findsOneWidget);
      expect(
        find.descendant(of: ringSlot, matching: find.byType(CustomPaint)),
        findsOneWidget,
      );

      // Release — completes the tap callback.
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tapped, isTrue);

      // After the full animation duration the ring should have collapsed
      // back to SizedBox.shrink (progress == 1.0 → invisible branch).
      await tester.pump(HeroFeedbackSurface.ringDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.descendant(of: ringSlot, matching: find.byType(CustomPaint)),
        findsNothing,
      );
    });
  });

  group('swipe flash', () {
    testWidgets('flashSwipe(1) renders › glyph then fades out', (tester) async {
      final key = GlobalKey<HeroFeedbackSurfaceState>();
      await tester.pumpWidget(host(
        SizedBox(
          width: 400,
          height: 400,
          child: HeroFeedbackSurface(
            key: key,
            onTap: () {},
            onHorizontalDragUpdate: (_) {},
            onHorizontalDragEnd: (_) {},
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ));

      // Idle — no glyph.
      expect(find.text('›'), findsNothing);
      expect(find.text('‹'), findsNothing);

      key.currentState!.flashSwipe(1);
      // Pump enough to land mid-envelope (~0.5 progress).
      await tester.pump(); // schedule first frame
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('›'), findsOneWidget);
      expect(find.text('‹'), findsNothing);

      // Drive the animation to completion — the glyph should be gone.
      await tester.pump(HeroFeedbackSurface.swipeFlashDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('›'), findsNothing);
    });

    testWidgets('flashSwipe(-1) renders ‹ glyph', (tester) async {
      final key = GlobalKey<HeroFeedbackSurfaceState>();
      await tester.pumpWidget(host(
        SizedBox(
          width: 400,
          height: 400,
          child: HeroFeedbackSurface(
            key: key,
            onTap: () {},
            onHorizontalDragUpdate: (_) {},
            onHorizontalDragEnd: (_) {},
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ));

      key.currentState!.flashSwipe(-1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('‹'), findsOneWidget);
      expect(find.text('›'), findsNothing);

      await tester.pump(HeroFeedbackSurface.swipeFlashDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('‹'), findsNothing);
    });
  });

  group('card swipe (B-039)', () {
    FractionalTranslation cardSlide(WidgetTester tester) =>
        tester.widget<FractionalTranslation>(
          find.byKey(HeroFeedbackSurface.cardSlideKey),
        );

    testWidgets('triggerSwipe(isNext: true) slides the card off LEFT then '
        'settles back to rest', (tester) async {
      final key = GlobalKey<HeroFeedbackSurfaceState>();
      await tester.pumpWidget(host(
        SizedBox(
          width: 400,
          height: 400,
          child: HeroFeedbackSurface(
            key: key,
            onTap: () {},
            onHorizontalDragUpdate: (_) {},
            onHorizontalDragEnd: (_) {},
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ));

      // At rest: identity transform (no layout / hit-test impact).
      expect(cardSlide(tester).translation, Offset.zero);
      // The › glyph confirms the flash fires alongside the slide for `next`.
      expect(find.text('›'), findsNothing);

      key.currentState!.triggerSwipe(isNext: true);
      await tester.pump(); // schedule first frame
      await tester.pump(const Duration(milliseconds: 75)); // ~t=0.25

      expect(cardSlide(tester).translation.dx, lessThan(0),
          reason: 'B-039: for `next` the outgoing card must slide off to the '
              'LEFT (negative dx).');
      expect(find.text('›'), findsOneWidget,
          reason: 'B-039: `next` swipe also fires the › edge flash.');

      // Drive the full slide; it must return to the identity transform.
      await tester.pump(HeroFeedbackSurface.cardSwipeDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(cardSlide(tester).translation.dx, closeTo(0, 0.001),
          reason: 'B-039: the card must settle back at rest after the slide.');
    });

    testWidgets('triggerSwipe(isNext: false) slides the card off RIGHT',
        (tester) async {
      final key = GlobalKey<HeroFeedbackSurfaceState>();
      await tester.pumpWidget(host(
        SizedBox(
          width: 400,
          height: 400,
          child: HeroFeedbackSurface(
            key: key,
            onTap: () {},
            onHorizontalDragUpdate: (_) {},
            onHorizontalDragEnd: (_) {},
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ));

      key.currentState!.triggerSwipe(isNext: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));

      expect(cardSlide(tester).translation.dx, greaterThan(0),
          reason: 'B-039: for `previous` the outgoing card must slide off to '
              'the RIGHT (positive dx).');
      expect(find.text('‹'), findsOneWidget,
          reason: 'B-039: `previous` swipe fires the ‹ edge flash.');

      await tester.pump(HeroFeedbackSurface.cardSwipeDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(cardSlide(tester).translation.dx, closeTo(0, 0.001));
    });
  });

  group('gesture pass-through', () {
    testWidgets('horizontal drag callback fires', (tester) async {
      int drags = 0;
      DragEndDetails? endDetails;
      await tester.pumpWidget(host(
        SizedBox(
          width: 400,
          height: 400,
          child: HeroFeedbackSurface(
            onTap: () {},
            onHorizontalDragUpdate: (_) => drags++,
            onHorizontalDragEnd: (d) => endDetails = d,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ));

      await tester.drag(
        find.byType(HeroFeedbackSurface),
        const Offset(200, 0),
      );
      await tester.pump();
      expect(drags, greaterThan(0));
      expect(endDetails, isNotNull);
    });
  });
}
