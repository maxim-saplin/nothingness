import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

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

    controller = PlaybackController(
      transport: transport,
      playlist: playlist,
      preflightFileExists: true,
      fileExists: (path) async => path != '/missing.mp3',
      captureRecentLogs: true,
    );
    await controller.init();
  });

  tearDown(() async {
    await controller.dispose();
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
    'diagnosticsSnapshot includes lastError + recentLogs after preflight miss',
    () async {
      await controller.setQueue(const [
        AudioTrack(path: '/missing.mp3', title: 'missing'),
        AudioTrack(path: '/ok.mp3', title: 'ok'),
      ]);

      final snap = controller.diagnosticsSnapshot();

      expect(snap['queueLength'], 2);
      expect(snap['failedTrackPaths'], contains('/missing.mp3'));

      final lastError = snap['lastError'] as Map;
      expect(lastError['path'], '/missing.mp3');
      expect(lastError['reason'], 'preflight_missing');

      final logs = (snap['recentLogs'] as List).cast<String>();
      expect(logs.any((l) => l.contains('PreflightMissing')), true);
    },
  );

  test(
    'tap on preflight-missing track skips without transient selection',
    () async {
      final seenIndices = <int?>[];
      controller.currentIndexNotifier.addListener(() {
        seenIndices.add(controller.currentIndexNotifier.value);
      });

      await controller.setQueue(const [
        AudioTrack(path: '/missing.mp3', title: 'missing'),
        AudioTrack(path: '/ok.mp3', title: 'ok'),
      ], startIndex: 1);
      await Future.delayed(const Duration(milliseconds: 50));

      seenIndices.clear();

      await controller.playFromQueueIndex(0);
      await Future.delayed(const Duration(milliseconds: 80));

      expect(controller.currentIndexNotifier.value, 1);
      expect(controller.queueNotifier.value[0].isNotFound, true);
      expect(seenIndices.whereType<int>(), isNot(contains(0)));
    },
  );

  test('songInfo notifier does not emit when state is unchanged', () async {
    await controller.setQueue(const [AudioTrack(path: '/ok.mp3', title: 'ok')]);
    await Future.delayed(const Duration(milliseconds: 80));

    var emissions = 0;
    void listener() {
      emissions += 1;
    }

    controller.songInfoNotifier.addListener(listener);
    await Future.delayed(const Duration(milliseconds: 900));
    controller.songInfoNotifier.removeListener(listener);

    expect(emissions, 0);
  });

  test('songInfo notifier emits when position changes', () async {
    await controller.setQueue(const [AudioTrack(path: '/ok.mp3', title: 'ok')]);
    await Future.delayed(const Duration(milliseconds: 80));

    var emissions = 0;
    void listener() {
      emissions += 1;
    }

    controller.songInfoNotifier.addListener(listener);
    transport.emitPosition(const Duration(seconds: 1));
    await Future.delayed(const Duration(milliseconds: 400));
    controller.songInfoNotifier.removeListener(listener);

    expect(emissions, greaterThanOrEqualTo(1));
  });
}
