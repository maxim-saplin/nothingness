import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import 'mock_audio_transport.dart';

/// Helper to wait until [predicate] returns true, with a timeout.
Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(step);
  }
  throw TestFailure('Predicate not satisfied within ${timeout.inMilliseconds}ms');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MockAudioTransport transport;
  late PlaylistStore playlist;
  late PlaybackController controller;
  var testNumber = 0;

  setUp(() async {
    testNumber++;
    tempDir = await Directory.systemTemp.createTemp(
      'playback_controller_intr_$testNumber',
    );
    Hive.init(tempDir.path);

    transport = MockAudioTransport();
    playlist = PlaylistStore(
      hive: Hive,
      hiveInitializer: () async {},
      boxOpener: (hive) =>
          hive.openBox<dynamic>('playlistBox_intr_$testNumber'),
    );

    controller = PlaybackController(
      transport: transport,
      playlist: playlist,
      preflightFileExists: false,
      captureRecentLogs: true,
    );
    await controller.init();
  });

  tearDown(() async {
    await controller.dispose();
    try {
      if (Hive.isBoxOpen('playlistBox_intr_$testNumber')) {
        await Hive.box('playlistBox_intr_$testNumber').close();
      }
    } catch (_) {}
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> startPlaying() async {
    await controller.setQueue(const [
      AudioTrack(path: '/a.mp3', title: 'a'),
      AudioTrack(path: '/b.mp3', title: 'b'),
    ]);
    await _waitFor(() => controller.isPlayingNotifier.value == true);
  }

  test('playing → interruption(begin, pause) → paused, intent preserved',
      () async {
    await startPlaying();
    final playsBefore = transport.playCalls.length;
    final pausesBefore = transport.pauseCalls.length;

    controller.debugSimulateInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    await _waitFor(() => controller.isPlayingNotifier.value == false);

    expect(controller.userIntent, PlayIntent.play);
    expect(transport.pauseCalls.length, pausesBefore + 1);
    expect(transport.playCalls.length, playsBefore);
  });

  test('after pause-interruption, end resumes playback', () async {
    await startPlaying();

    controller.debugSimulateInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    await _waitFor(() => controller.isPlayingNotifier.value == false);

    final playsBefore = transport.playCalls.length;
    controller.debugSimulateInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    await _waitFor(() => controller.isPlayingNotifier.value == true);

    expect(transport.playCalls.length, playsBefore + 1);
  });

  test('paused → interruption(begin, pause) → no extra pause call', () async {
    await startPlaying();
    await controller.playPause();
    await _waitFor(() => controller.isPlayingNotifier.value == false);

    final pausesBefore = transport.pauseCalls.length;
    final playsBefore = transport.playCalls.length;

    controller.debugSimulateInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(transport.pauseCalls.length, pausesBefore);
    expect(transport.playCalls.length, playsBefore);
    // Now end the interruption — should NOT auto-resume (we weren't paused
    // by the interruption).
    controller.debugSimulateInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.isPlayingNotifier.value, false);
    expect(transport.playCalls.length, playsBefore);
  });

  test(
    'user pauses during interruption → no surprise resume on end',
    () async {
      await startPlaying();

      controller.debugSimulateInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await _waitFor(() => controller.isPlayingNotifier.value == false);

      // User explicitly flips intent to pause while interruption is active.
      await controller.playPause();
      expect(controller.userIntent, PlayIntent.pause);

      final playsBefore = transport.playCalls.length;
      controller.debugSimulateInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.isPlayingNotifier.value, false);
      expect(transport.playCalls.length, playsBefore);
    },
  );

  test('interruption(begin, duck) → no transport call', () async {
    await startPlaying();

    final pausesBefore = transport.pauseCalls.length;
    final playsBefore = transport.playCalls.length;

    controller.debugSimulateInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.duck),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(transport.pauseCalls.length, pausesBefore);
    expect(transport.playCalls.length, playsBefore);
    expect(controller.isPlayingNotifier.value, true);
  });

  test('interruption(end, unknown) when paused-by-interruption → stays paused',
      () async {
    await startPlaying();

    controller.debugSimulateInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    await _waitFor(() => controller.isPlayingNotifier.value == false);

    final playsBefore = transport.playCalls.length;
    controller.debugSimulateInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.unknown),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.isPlayingNotifier.value, false);
    expect(transport.playCalls.length, playsBefore);
  });

  test('playing → becomingNoisy → paused, intent=pause, no auto-resume',
      () async {
    await startPlaying();

    controller.debugSimulateBecomingNoisy();
    await _waitFor(() => controller.isPlayingNotifier.value == false);

    expect(controller.userIntent, PlayIntent.pause);

    // Subsequent interruption-end should NOT resume.
    final playsBefore = transport.playCalls.length;
    controller.debugSimulateInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.isPlayingNotifier.value, false);
    expect(transport.playCalls.length, playsBefore);
  });

  test('diagnosticsSnapshot includes audioEvents after interruption + noisy',
      () async {
    await startPlaying();

    controller.debugSimulateInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    controller.debugSimulateInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    controller.debugSimulateBecomingNoisy();

    final snap = controller.diagnosticsSnapshot();
    final events = (snap['audioEvents'] as List).cast<String>();

    expect(events.where((l) => l.contains('interruption')).length,
        greaterThanOrEqualTo(2));
    expect(events.any((l) => l.contains('becomingNoisy')), true);
  });
}
