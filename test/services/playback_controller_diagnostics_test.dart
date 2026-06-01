import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import '../support/pump_until.dart';
import 'mock_audio_transport.dart';

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
      'playback_controller_diag_$testNumber',
    );
    Hive.init(tempDir.path);

    transport = MockAudioTransport();
    playlist = PlaylistStore(
      hive: Hive,
      hiveInitializer: () async {},
      boxOpener: (hive) =>
          hive.openBox<dynamic>('playlistBox_diag_$testNumber'),
    );

    // A missing/unreadable track surfaces as a transport load failure (the
    // source of truth — there is no separate File.exists() preflight).
    transport.pathsToFailOnLoad.add('/missing.mp3');
    controller = PlaybackController(
      transport: transport,
      playlist: playlist,
      captureRecentLogs: true,
    );
    await controller.init();
  });

  tearDown(() async {
    await controller.shutdown();
    try {
      if (Hive.isBoxOpen('playlistBox_diag_$testNumber')) {
        await Hive.box('playlistBox_diag_$testNumber').close();
      }
    } catch (_) {}
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'diagnosticsSnapshot includes lastError + recentLogs after a load failure',
    () async {
      await controller.setQueue(const [
        AudioTrack(path: '/missing.mp3', title: 'missing'),
        AudioTrack(path: '/ok.mp3', title: 'ok'),
      ]);
      await pumpUntil(() => controller.queueNotifier.value[0].isNotFound);

      final snap = controller.diagnosticsSnapshot();

      expect(snap['queueLength'], 2);
      expect(snap['failedTrackPaths'], contains('/missing.mp3'));

      final lastError = snap['lastError'] as Map;
      expect(lastError['path'], '/missing.mp3');
      expect(lastError['reason'], 'transport_load_error');

      final logs = (snap['recentLogs'] as List).cast<String>();
      expect(logs.any((l) => l.contains('/missing.mp3')), true);
    },
  );

  test(
    'tap on a load-failing track lands cleanly on the next playable track',
    () async {
      await controller.setQueue(const [
        AudioTrack(path: '/missing.mp3', title: 'missing'),
        AudioTrack(path: '/ok.mp3', title: 'ok'),
      ], startIndex: 1);
      await pumpUntil(() => controller.currentIndexNotifier.value == 1);

      await controller.playFromQueueIndex(0);
      // Tapping the missing track 0 marks it not-found and skips to 1.
      // (The index commits optimistically before the load — so the hero can
      // advance at 60fps — then the load failure skips past it; the contract
      // is the *settled* state, not the absence of a transient flip.)
      await pumpUntil(() => controller.queueNotifier.value[0].isNotFound);

      expect(controller.currentIndexNotifier.value, 1);
      expect(controller.queueNotifier.value[0].isNotFound, true);
      expect(controller.isPlayingNotifier.value, true,
          reason: 'lands playing on the next track, not stuck/dead on 0');
    },
  );

  test('songInfo notifier does not emit when state is unchanged', () async {
    await controller.setQueue(const [AudioTrack(path: '/ok.mp3', title: 'ok')]);
    // Inherently time-based test (the position timer is the only emitter).
    // A fixed settle lets the initial emissions flush before we attach the
    // listener; the assertion below then observes a quiet, unchanged window.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    var emissions = 0;
    void listener() {
      emissions += 1;
    }

    controller.songInfoNotifier.addListener(listener);
    // Absence assertion: observe across several 300 ms position-timer ticks and
    // confirm no emission fires while the state is unchanged. This is an
    // intentional fixed observation window, not a settle-for-a-result wait.
    await Future.delayed(const Duration(milliseconds: 900));
    controller.songInfoNotifier.removeListener(listener);

    expect(emissions, 0);
  });

  test('songInfo notifier emits when position changes', () async {
    await controller.setQueue(const [AudioTrack(path: '/ok.mp3', title: 'ok')]);
    // Flush initial settle emissions before attaching the listener, so the
    // count below reflects only the position-change emit.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    var emissions = 0;
    void listener() {
      emissions += 1;
    }

    controller.songInfoNotifier.addListener(listener);
    transport.emitPosition(const Duration(seconds: 1));
    await pumpUntil(() => emissions >= 1);
    controller.songInfoNotifier.removeListener(listener);

    expect(emissions, greaterThanOrEqualTo(1));
  });
}
