import 'dart:io';
import 'dart:math';

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

  List<AudioTrack> createTracks(int count) {
    return List.generate(
      count,
      (i) => AudioTrack(
        path: '/queue/track_$i.mp3',
        title: 'Track $i',
      ),
    );
  }

  AudioTrack oneShotTrack() => const AudioTrack(
        path: '/oneshot/glass.flac',
        title: 'Glass',
      );

  setUp(() async {
    testNumber++;
    tempDir = await Directory.systemTemp.createTemp(
      'playback_controller_oneshot_$testNumber',
    );
    Hive.init(tempDir.path);

    transport = MockAudioTransport();
    playlist = PlaylistStore(
      hive: Hive,
      hiveInitializer: () async {},
      boxOpener: (hive) =>
          hive.openBox<dynamic>('playlistBox_oneshot_$testNumber'),
      random: Random(7),
    );

    controller = PlaybackController(
      transport: transport,
      playlist: playlist,
      preflightFileExists: false,
    );
    await controller.init();
  });

  tearDown(() async {
    await controller.dispose();
    try {
      if (Hive.isBoxOpen('playlistBox_oneshot_$testNumber')) {
        await Hive.box('playlistBox_oneshot_$testNumber').close();
      }
    } catch (_) {}
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('playOneShot', () {
    test('natural end on non-tail position resumes at start + 1', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks, startIndex: 1);
      // Sanity: queue is playing track index 1.
      expect(controller.currentIndexNotifier.value, 1);
      expect(controller.isPlayingNotifier.value, isTrue);

      transport.resetCalls();
      await controller.playOneShot(oneShotTrack());

      expect(controller.isOneShot, isTrue);
      expect(controller.isOneShotNotifier.value, isTrue);
      expect(transport.loadedPath, '/oneshot/glass.flac');

      // Natural end: should restore queue at index 2.
      transport.emitTrackEnded();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.isOneShot, isFalse);
      expect(controller.isOneShotNotifier.value, isFalse);
      expect(controller.currentIndexNotifier.value, 2);
      expect(transport.loadedPath, '/queue/track_2.mp3');
      expect(controller.isPlayingNotifier.value, isTrue);
    });

    test('natural end on tail position stops without advancing', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks, startIndex: 2);
      expect(controller.currentIndexNotifier.value, 2);

      await controller.playOneShot(oneShotTrack());
      expect(controller.isOneShot, isTrue);

      transport.emitTrackEnded();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Should stop — no advance past the tail.
      expect(controller.isOneShot, isFalse);
      expect(controller.isPlayingNotifier.value, isFalse);
      expect(controller.currentIndexNotifier.value, 2);
    });

    test('explicit next() during one-shot exits and steps from captured position',
        () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks, startIndex: 1);

      await controller.playOneShot(oneShotTrack());
      expect(controller.isOneShot, isTrue);

      // Explicit next during one-shot — should advance to start + 1 = index 2.
      await controller.next();

      expect(controller.isOneShot, isFalse);
      expect(controller.currentIndexNotifier.value, 2);
      expect(transport.loadedPath, '/queue/track_2.mp3');
    });

    test('repeatOne loops via _handleTrackEnded without finishing one-shot',
        () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks, startIndex: 0);

      final track = oneShotTrack();
      await controller.playOneShot(track, repeatOne: true);
      expect(controller.isOneShot, isTrue);
      expect(controller.oneShotTrack?.path, track.path);

      transport.resetCalls();
      transport.emitTrackEnded();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Still in one-shot, looped back to the same track.
      expect(controller.isOneShot, isTrue);
      expect(controller.isOneShotNotifier.value, isTrue);
      expect(controller.oneShotTrack?.path, track.path);
      expect(transport.loadedPath, track.path);
      // Queue must not have advanced.
      expect(controller.currentIndexNotifier.value, 0);
    });
  });
}
