import 'dart:io';
import 'dart:math';

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
    );
    await controller.init();
  });

  tearDown(() async {
    await controller.shutdown();
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
      await pumpUntil(
        () => !controller.isOneShot &&
            controller.currentIndexNotifier.value == 2 &&
            transport.loadedPath == '/queue/track_2.mp3',
      );

      expect(controller.isOneShot, isFalse);
      expect(controller.isOneShotNotifier.value, isFalse);
      expect(controller.currentIndexNotifier.value, 2);
      expect(transport.loadedPath, '/queue/track_2.mp3');
      expect(controller.isPlayingNotifier.value, isTrue);
    });

    test('tapping a missing file stops cleanly without throwing and flags it '
        'not-found (load failure is the source of truth)', () async {
      final missTransport = MockAudioTransport();
      final missPlaylist = PlaylistStore(
        hive: Hive,
        hiveInitializer: () async {},
        boxOpener: (hive) =>
            hive.openBox<dynamic>('playlistBox_oneshot_pf_$testNumber'),
        random: Random(7),
      );
      // The tapped file is gone → the transport load throws (as the real
      // SoLoud transport does for a missing/unreadable file).
      missTransport.pathsToFailOnLoad.add('/oneshot/glass.flac');
      final missController = PlaybackController(
        transport: missTransport,
        playlist: missPlaylist,
      );
      await missController.init();
      missTransport.resetCalls();

      // Must not throw: the one-shot catch handles the load failure, flags the
      // track not-found, and stops cleanly (no unhandled SoLoudFileNotFound).
      await missController.playOneShot(oneShotTrack());

      expect(missController.isOneShotNotifier.value, isFalse);
      expect(missController.isPlayingNotifier.value, isFalse);
      // The transport WAS asked to load it (no preflight short-circuit); the
      // failure is what stops it cleanly.
      expect(missTransport.loadCalls, contains('/oneshot/glass.flac'));

      await missController.shutdown();
      if (Hive.isBoxOpen('playlistBox_oneshot_pf_$testNumber')) {
        await Hive.box('playlistBox_oneshot_pf_$testNumber').close();
      }
    });

    test('a TRANSIENT one-shot load failure stops cleanly but does NOT '
        'permanently flag the track not-found', () async {
      final txTransport = MockAudioTransport();
      final txPlaylist = PlaylistStore(
        hive: Hive,
        hiveInitializer: () async {},
        boxOpener: (hive) =>
            hive.openBox<dynamic>('playlistBox_oneshot_tx_$testNumber'),
        random: Random(7),
      );
      txTransport.pathsToFailTransiently.add('/oneshot/glass.flac');
      final txController = PlaybackController(
        transport: txTransport,
        playlist: txPlaylist,
      );
      // A real queue so we can observe the not-found flag isn't set.
      await txController.setQueue(createTracks(3));
      txTransport.resetCalls();

      await txController.playOneShot(oneShotTrack());

      expect(txController.isOneShotNotifier.value, isFalse);
      expect(txController.isPlayingNotifier.value, isFalse);
      expect(txTransport.loadCalls, contains('/oneshot/glass.flac'));
      // A transient blip must NOT mark the track missing in the queue.
      expect(
        txController.diagnosticsSnapshot()['failedTrackPaths'],
        isNot(contains('/oneshot/glass.flac')),
      );

      await txController.shutdown();
      if (Hive.isBoxOpen('playlistBox_oneshot_tx_$testNumber')) {
        await Hive.box('playlistBox_oneshot_tx_$testNumber').close();
      }
    });

    test('natural end on tail position stops without advancing', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks, startIndex: 2);
      expect(controller.currentIndexNotifier.value, 2);

      await controller.playOneShot(oneShotTrack());
      expect(controller.isOneShot, isTrue);

      transport.emitTrackEnded();
      await pumpUntil(() => !controller.isOneShot);

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
      // repeat-one reloads the same track in place; wait for that reload.
      await pumpUntil(() => transport.loadCalls.contains(track.path));

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
