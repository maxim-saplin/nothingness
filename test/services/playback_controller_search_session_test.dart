import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import '../support/pump_until.dart';
import 'mock_audio_transport.dart';

/// Tests for B-014: search results should install as a sub-queue (a "search
/// session"), and dismissing search should restore the original queue
/// without interrupting the currently-playing track.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MockAudioTransport transport;
  late PlaylistStore playlist;
  late PlaybackController controller;
  var testNumber = 0;

  List<AudioTrack> originalTracks() => const <AudioTrack>[
        AudioTrack(path: '/queue/a.mp3', title: 'A'),
        AudioTrack(path: '/queue/b.mp3', title: 'B'),
        AudioTrack(path: '/queue/c.mp3', title: 'C'),
      ];

  List<AudioTrack> searchResults() => const <AudioTrack>[
        AudioTrack(path: '/lib/the_strokes.mp3', title: 'The Strokes'),
        AudioTrack(path: '/lib/the_offspring.mp3', title: 'The Offspring'),
        AudioTrack(path: '/lib/the_clash.mp3', title: 'The Clash'),
      ];

  setUp(() async {
    testNumber++;
    tempDir = await Directory.systemTemp.createTemp(
      'playback_controller_search_session_$testNumber',
    );
    Hive.init(tempDir.path);

    transport = MockAudioTransport();
    playlist = PlaylistStore(
      hive: Hive,
      hiveInitializer: () async {},
      boxOpener: (hive) =>
          hive.openBox<dynamic>('playlistBox_search_$testNumber'),
      random: Random(11),
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
      if (Hive.isBoxOpen('playlistBox_search_$testNumber')) {
        await Hive.box('playlistBox_search_$testNumber').close();
      }
    } catch (_) {}
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('enterSearchSession', () {
    test('snapshots prior queue + currentIndex and installs results',
        () async {
      await controller.setQueue(originalTracks(), startIndex: 1);
      expect(controller.currentIndexNotifier.value, 1);
      expect(controller.queueNotifier.value.length, 3);

      transport.resetCalls();
      await controller.enterSearchSession(searchResults(), 0);

      expect(controller.isInSearchSession, isTrue);
      // Queue swapped to the search-results list.
      expect(controller.queueNotifier.value.length, 3);
      expect(controller.queueNotifier.value[0].path, '/lib/the_strokes.mp3');
      expect(controller.queueNotifier.value[1].path, '/lib/the_offspring.mp3');
      // Active item is the tapped one.
      expect(controller.currentIndexNotifier.value, 0);
      expect(transport.loadedPath, '/lib/the_strokes.mp3');
      expect(controller.isPlayingNotifier.value, isTrue);
    });

    test('starts at tappedIndex even when not zero', () async {
      await controller.setQueue(originalTracks(), startIndex: 0);

      await controller.enterSearchSession(searchResults(), 2);

      expect(controller.currentIndexNotifier.value, 2);
      expect(transport.loadedPath, '/lib/the_clash.mp3');
    });

    test('subsequent results play in order via natural end', () async {
      await controller.setQueue(originalTracks(), startIndex: 0);
      await controller.enterSearchSession(searchResults(), 0);

      // Natural end of the first search-result track.
      transport.emitTrackEnded();
      await pumpUntil(() => controller.currentIndexNotifier.value == 1 &&
          transport.loadedPath == '/lib/the_offspring.mp3');

      expect(controller.isInSearchSession, isTrue);
      expect(controller.currentIndexNotifier.value, 1);
      expect(transport.loadedPath, '/lib/the_offspring.mp3');
    });
  });

  group('exitSearchSession', () {
    test('restores prior queue and points to savedIndex when active track '
        'is not in the restored queue', () async {
      await controller.setQueue(originalTracks(), startIndex: 1);
      await controller.enterSearchSession(searchResults(), 0);

      transport.resetCalls();
      await controller.exitSearchSession();

      expect(controller.isInSearchSession, isFalse);
      // Original queue restored (3 tracks).
      expect(controller.queueNotifier.value.length, 3);
      expect(controller.queueNotifier.value[0].path, '/queue/a.mp3');
      expect(controller.queueNotifier.value[1].path, '/queue/b.mp3');
      expect(controller.queueNotifier.value[2].path, '/queue/c.mp3');
      // Active search track is NOT in the restored queue → savedIndex (1).
      expect(controller.currentIndexNotifier.value, 1);
      // Currently-playing track must keep playing — we did not reload another
      // track on top of the search result.
      expect(transport.loadCalls, isEmpty,
          reason: 'exitSearchSession must not reload any track');
    });

    test('exitSearchSession with no active session is a no-op', () async {
      await controller.setQueue(originalTracks(), startIndex: 1);

      transport.resetCalls();
      await controller.exitSearchSession();

      // State unchanged.
      expect(controller.isInSearchSession, isFalse);
      expect(controller.queueNotifier.value.length, 3);
      expect(controller.currentIndexNotifier.value, 1);
      expect(transport.loadCalls, isEmpty);
    });

    test('when the active search track is also present in the restored queue, '
        'currentIndex points to its position there', () async {
      // Prior queue contains one of the search results.
      const overlap = AudioTrack(
        path: '/lib/the_offspring.mp3',
        title: 'The Offspring',
      );
      final prior = <AudioTrack>[
        const AudioTrack(path: '/queue/x.mp3', title: 'X'),
        overlap,
        const AudioTrack(path: '/queue/y.mp3', title: 'Y'),
      ];
      await controller.setQueue(prior, startIndex: 0);

      // Enter a search session that includes the overlap; tap it.
      await controller.enterSearchSession(searchResults(), 1);
      expect(transport.loadedPath, '/lib/the_offspring.mp3');

      transport.resetCalls();
      await controller.exitSearchSession();

      expect(controller.isInSearchSession, isFalse);
      // currentIndex points to overlap's index in restored queue (was 1).
      expect(controller.currentIndexNotifier.value, 1);
      // No reload of the playing track.
      expect(transport.loadCalls, isEmpty);
    });

    test('natural end after exit advances within the restored queue',
        () async {
      await controller.setQueue(originalTracks(), startIndex: 1);
      await controller.enterSearchSession(searchResults(), 0);
      await controller.exitSearchSession();

      // Active track is not in restored queue → savedIndex == 1 (B in
      // originalTracks). The currently-playing track keeps playing; on its
      // natural end the controller should advance to index 2 of the
      // RESTORED queue (C), not anything from the search list.
      transport.resetCalls();
      transport.emitTrackEnded();
      await pumpUntil(() => controller.currentIndexNotifier.value == 2 &&
          transport.loadedPath == '/queue/c.mp3');

      expect(controller.currentIndexNotifier.value, 2);
      expect(transport.loadedPath, '/queue/c.mp3');
    });
  });

  group('re-enter while active', () {
    test('does not re-snapshot — exit still restores the ORIGINAL queue',
        () async {
      await controller.setQueue(originalTracks(), startIndex: 1);
      await controller.enterSearchSession(searchResults(), 0);

      // Re-enter with a different result list.
      final second = <AudioTrack>[
        const AudioTrack(path: '/lib/u2.mp3', title: 'U2'),
        const AudioTrack(path: '/lib/muse.mp3', title: 'Muse'),
      ];
      await controller.enterSearchSession(second, 1);

      // Session still active; queue is the new results.
      expect(controller.isInSearchSession, isTrue);
      expect(controller.queueNotifier.value.length, 2);
      expect(controller.currentIndexNotifier.value, 1);
      expect(transport.loadedPath, '/lib/muse.mp3');

      // Exit must restore the ORIGINAL queue (the one before the FIRST
      // enter), not the first search-result list.
      await controller.exitSearchSession();
      expect(controller.queueNotifier.value.length, 3);
      expect(controller.queueNotifier.value[0].path, '/queue/a.mp3');
      // savedIndex was 1.
      expect(controller.currentIndexNotifier.value, 1);
    });
  });
}
