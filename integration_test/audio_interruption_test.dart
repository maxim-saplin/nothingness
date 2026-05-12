import 'package:audio_session/audio_session.dart';
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
    if (condition()) return;
  }
  throw TestFailure('Condition not met within ${timeout.inMilliseconds}ms');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('audio interruption integration', () {
    setUp(() {
      TestHarness.instance.reset();
    });

    testWidgets('phone-call style interruption pauses then resumes', (
      tester,
    ) async {
      await app.main();
      await tester.pumpAndSettle();

      final h = TestHarness.instance;
      h.setExistsMap(<String, bool>{
        '/a.mp3': true,
        '/b.mp3': true,
      });

      await h.setQueue([
        const AudioTrack(path: '/a.mp3', title: 'a'),
        const AudioTrack(path: '/b.mp3', title: 'b'),
      ]);
      await tester.pumpAndSettle();

      // Start playback explicitly via the test panel so the test exercises the
      // same play() path the user does.
      await _pumpUntil(tester, () {
        return find.textContaining('playing=true').evaluate().isNotEmpty;
      });

      // Simulate phone call begin → transient focus loss.
      h.simulateInterruption(begin: true, type: AudioInterruptionType.pause);
      await _pumpUntil(tester, () {
        return find.textContaining('playing=false').evaluate().isNotEmpty;
      });

      // Simulate phone call end → focus gain.
      h.simulateInterruption(begin: false, type: AudioInterruptionType.pause);
      await _pumpUntil(tester, () {
        return find.textContaining('playing=true').evaluate().isNotEmpty;
      });
    });

    testWidgets('becoming noisy pauses and does not auto-resume', (
      tester,
    ) async {
      await app.main();
      await tester.pumpAndSettle();

      final h = TestHarness.instance;
      h.setExistsMap(<String, bool>{'/a.mp3': true});

      await h.setQueue([
        const AudioTrack(path: '/a.mp3', title: 'a'),
      ]);
      await tester.pumpAndSettle();

      await _pumpUntil(tester, () {
        return find.textContaining('playing=true').evaluate().isNotEmpty;
      });

      h.simulateBecomingNoisy();
      await _pumpUntil(tester, () {
        return find.textContaining('playing=false').evaluate().isNotEmpty;
      });

      // Focus gain event afterwards must NOT auto-resume since user intent is
      // now "pause" (per Android guidance).
      h.simulateInterruption(begin: false, type: AudioInterruptionType.pause);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('playing=true'), findsNothing);
    });

    testWidgets('queue still navigable after interruption', (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      final h = TestHarness.instance;
      h.setExistsMap(<String, bool>{
        '/a.mp3': true,
        '/b.mp3': true,
      });

      await h.setQueue([
        const AudioTrack(path: '/a.mp3', title: 'a'),
        const AudioTrack(path: '/b.mp3', title: 'b'),
      ]);
      await tester.pumpAndSettle();

      h.simulateInterruption(begin: true, type: AudioInterruptionType.pause);
      await _pumpUntil(tester, () {
        return find.textContaining('playing=false').evaluate().isNotEmpty;
      });

      // While interrupted, tap Next — must advance and resume.
      await tester.tap(find.byKey(TestKeys.next));
      await tester.pumpAndSettle();

      expect(find.textContaining('idx=1'), findsOneWidget);
    });
  });
}
