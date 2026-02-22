import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:nothingness/main_test.dart' as app;
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/testing/test_harness.dart';
import 'package:nothingness/testing/test_overlay.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  Duration step = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (condition()) {
      return;
    }
  }
  throw TestFailure('Condition not met within ${timeout.inMilliseconds}ms');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('missing-track consistency (no audio files)', () {
    setUp(() {
      TestHarness.instance.reset();
    });

    testWidgets('tap missing track → marked red → advances to next playable', (
      tester,
    ) async {
      await app.main();
      await tester.pumpAndSettle();

      final h = TestHarness.instance;
      h.setExistsMap(<String, bool>{
        '/t0.mp3': false,
        '/t1.mp3': true,
        '/t2.mp3': true,
      });

      await h.setQueue([
        const AudioTrack(path: '/t0.mp3', title: 't0'),
        const AudioTrack(path: '/t1.mp3', title: 't1'),
        const AudioTrack(path: '/t2.mp3', title: 't2'),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestKeys.queueItem(0)));

      await _pumpUntil(tester, () {
        final missingMarked = find
            .descendant(
              of: find.byKey(TestKeys.queueItem(0)),
              matching: find.textContaining('(Not found)'),
            )
            .evaluate()
            .isNotEmpty;
        final advancedToNext = find
            .textContaining('idx=1')
            .evaluate()
            .isNotEmpty;
        return missingMarked && advancedToNext;
      });

      expect(
        find.descendant(
          of: find.byKey(TestKeys.queueItem(0)),
          matching: find.textContaining('(Not found)'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('idx=1'), findsOneWidget);
    });

    testWidgets('next skips known-missing (never land-and-pause)', (
      tester,
    ) async {
      await app.main();
      await tester.pumpAndSettle();

      final h = TestHarness.instance;
      h.setExistsMap(<String, bool>{
        '/a.mp3': true,
        '/missing.mp3': false,
        '/b.mp3': true,
      });

      await h.setQueue([
        const AudioTrack(path: '/a.mp3', title: 'a'),
        const AudioTrack(path: '/missing.mp3', title: 'missing'),
        const AudioTrack(path: '/b.mp3', title: 'b'),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestKeys.next));
      await tester.pumpAndSettle();

      expect(find.textContaining('idx=2'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(TestKeys.queueItem(1)),
          matching: find.textContaining('(Not found)'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('previous skips known-missing backwards', (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      final h = TestHarness.instance;
      h.setExistsMap(<String, bool>{
        '/a.mp3': true,
        '/missing.mp3': false,
        '/b.mp3': true,
      });

      await h.setQueue([
        const AudioTrack(path: '/a.mp3', title: 'a'),
        const AudioTrack(path: '/missing.mp3', title: 'missing'),
        const AudioTrack(path: '/b.mp3', title: 'b'),
      ], startIndex: 2);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestKeys.prev));
      await tester.pumpAndSettle();

      expect(find.textContaining('idx=0'), findsOneWidget);
    });

    testWidgets('natural end → advances and skips missing', (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      final h = TestHarness.instance;
      h.setExistsMap(<String, bool>{
        '/a.mp3': true,
        '/missing.mp3': false,
        '/b.mp3': true,
      });

      await h.setQueue([
        const AudioTrack(path: '/a.mp3', title: 'a'),
        const AudioTrack(path: '/missing.mp3', title: 'missing'),
        const AudioTrack(path: '/b.mp3', title: 'b'),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestKeys.emitEnded));
      await tester.pumpAndSettle();

      expect(find.textContaining('idx=2'), findsOneWidget);
    });

    testWidgets('all missing → stops cleanly (not playing) and marks all', (
      tester,
    ) async {
      await app.main();
      await tester.pumpAndSettle();

      final h = TestHarness.instance;
      h.setExistsMap(<String, bool>{'/m0.mp3': false, '/m1.mp3': false});

      await h.setQueue([
        const AudioTrack(path: '/m0.mp3', title: 'm0'),
        const AudioTrack(path: '/m1.mp3', title: 'm1'),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('playing=false'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(TestKeys.queueItem(0)),
          matching: find.textContaining('(Not found)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(TestKeys.queueItem(1)),
          matching: find.textContaining('(Not found)'),
        ),
        findsOneWidget,
      );
    });
  });
}
