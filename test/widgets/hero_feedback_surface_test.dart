import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/theme_id.dart';
import 'package:nothingness/theme/themes.dart';
import 'package:nothingness/widgets/hero_feedback_surface.dart';

/// Hero touch surface: tap-zones (prev/playpause/next), drag-to-seek, and the
/// tap-ring / edge-flash feedback overlays.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: buildAppTheme(id: ThemeId.void_, brightness: Brightness.dark),
      home: Scaffold(body: child),
    );
  }

  /// Builds the surface with recording callbacks. Position/duration default to
  /// a 60 s track at 10 s in unless overridden.
  ({
    Widget widget,
    List<String> events,
    List<Duration> seeks,
  }) build({
    GlobalKey<HeroFeedbackSurfaceState>? key,
    int positionMs = 10000,
    int durationMs = 60000,
  }) {
    final events = <String>[];
    final seeks = <Duration>[];
    final w = SizedBox(
      width: 400,
      height: 400,
      child: HeroFeedbackSurface(
        key: key,
        onPlayPause: () => events.add('playpause'),
        onPrevious: () => events.add('previous'),
        onNext: () => events.add('next'),
        onSeek: (d) => seeks.add(d),
        positionMs: () => positionMs,
        durationMs: () => durationMs,
        child: const ColoredBox(color: Colors.black),
      ),
    );
    return (widget: w, events: events, seeks: seeks);
  }

  group('tap ring', () {
    testWidgets('appears on tap-down and disappears after the animation',
        (tester) async {
      final b = build();
      await tester.pumpWidget(host(b.widget));

      // Pre-tap: the ring slot widget isn't mounted yet.
      expect(find.byKey(HeroFeedbackSurface.tapRingKey), findsNothing);

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(HeroFeedbackSurface)));
      // Let kPressTimeout elapse so onTapDown fires, then commit the setState.
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 16));

      final ringSlot = find.byKey(HeroFeedbackSurface.tapRingKey);
      expect(ringSlot, findsOneWidget);
      expect(
        find.descendant(of: ringSlot, matching: find.byType(CustomPaint)),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pump(HeroFeedbackSurface.ringDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.descendant(of: ringSlot, matching: find.byType(CustomPaint)),
        findsNothing,
      );
    });
  });

  group('tap zones', () {
    Offset at(WidgetTester tester, double fractionX) {
      final rect = tester.getRect(find.byType(HeroFeedbackSurface));
      return Offset(rect.left + rect.width * fractionX, rect.center.dy);
    }

    testWidgets('left third taps fire previous', (tester) async {
      final b = build();
      await tester.pumpWidget(host(b.widget));
      await tester.tapAt(at(tester, 1 / 6));
      await tester.pump();
      expect(b.events, ['previous']);
      // Left tap also flashes the ‹ glyph.
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('‹'), findsOneWidget);
    });

    testWidgets('centre third taps fire play/pause', (tester) async {
      final b = build();
      await tester.pumpWidget(host(b.widget));
      await tester.tapAt(at(tester, 1 / 2));
      await tester.pump();
      expect(b.events, ['playpause']);
    });

    testWidgets('right third taps fire next', (tester) async {
      final b = build();
      await tester.pumpWidget(host(b.widget));
      await tester.tapAt(at(tester, 5 / 6));
      await tester.pump();
      expect(b.events, ['next']);
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('›'), findsOneWidget);
    });
  });

  group('drag to seek', () {
    testWidgets('a rightward drag commits one relative seek on release',
        (tester) async {
      // 60 s track at 10 s; a +200 px drag over a 400 px width advances by
      // half the track (≈30 s) → target ≈ 40 s. Touch slop trims the first
      // ~18 px, so allow tolerance.
      final b = build(positionMs: 10000, durationMs: 60000);
      await tester.pumpWidget(host(b.widget));

      await tester.drag(
        find.byType(HeroFeedbackSurface),
        const Offset(200, 0),
      );
      await tester.pump();

      expect(b.seeks.length, 1, reason: 'exactly one seek per drag');
      expect(b.events, isEmpty, reason: 'a drag is not a tap');
      final secs = b.seeks.single.inMilliseconds / 1000.0;
      expect(secs, greaterThan(33));
      expect(secs, lessThan(40));
    });

    testWidgets('a leftward drag seeks backward', (tester) async {
      final b = build(positionMs: 40000, durationMs: 60000);
      await tester.pumpWidget(host(b.widget));
      await tester.drag(
        find.byType(HeroFeedbackSurface),
        const Offset(-200, 0),
      );
      await tester.pump();
      expect(b.seeks.length, 1);
      expect(b.seeks.single.inSeconds, lessThan(40));
    });

    testWidgets('the seek HUD shows the time readout while dragging',
        (tester) async {
      final b = build(positionMs: 10000, durationMs: 60000);
      await tester.pumpWidget(host(b.widget));

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(HeroFeedbackSurface)));
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();

      expect(find.byKey(HeroFeedbackSurface.seekHudKey), findsOneWidget);
      // Readout is "m:ss / m:ss".
      expect(find.textContaining(' / 1:00'), findsOneWidget);

      await gesture.up();
      await tester.pump();
      // HUD is gone once the drag ends.
      expect(find.byKey(HeroFeedbackSurface.seekHudKey), findsNothing);
    });

    testWidgets('with no duration the drag does not seek', (tester) async {
      final b = build(positionMs: 0, durationMs: 0);
      await tester.pumpWidget(host(b.widget));
      await tester.drag(
        find.byType(HeroFeedbackSurface),
        const Offset(200, 0),
      );
      await tester.pump();
      expect(b.seeks, isEmpty);
    });
  });

  group('edge flash', () {
    testWidgets('flashSwipe(1) renders › glyph then fades out', (tester) async {
      final key = GlobalKey<HeroFeedbackSurfaceState>();
      final b = build(key: key);
      await tester.pumpWidget(host(b.widget));

      expect(find.text('›'), findsNothing);
      expect(find.text('‹'), findsNothing);

      key.currentState!.flashSwipe(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('›'), findsOneWidget);
      expect(find.text('‹'), findsNothing);

      await tester.pump(HeroFeedbackSurface.swipeFlashDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('›'), findsNothing);
    });

    testWidgets('flashSwipe(-1) renders ‹ glyph', (tester) async {
      final key = GlobalKey<HeroFeedbackSurfaceState>();
      final b = build(key: key);
      await tester.pumpWidget(host(b.widget));

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
}
