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
        path: '/path/track_$i.mp3',
        title: 'Track $i',
      ),
    );
  }

  setUp(() async {
    testNumber++;
    tempDir = await Directory.systemTemp.createTemp(
      'playback_controller_regressions_$testNumber',
    );
    Hive.init(tempDir.path);

    transport = MockAudioTransport();
    playlist = PlaylistStore(
      hive: Hive,
      hiveInitializer: () async {},
      boxOpener: (hive) => hive.openBox<dynamic>('playlistBox_reg_$testNumber'),
      random: Random(2),
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
      if (Hive.isBoxOpen('playlistBox_reg_$testNumber')) {
        await Hive.box('playlistBox_reg_$testNumber').close();
      }
    } catch (_) {}
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('previous() on stopped last track restarts last track', () async {
    final tracks = createTracks(5);
    await controller.setQueue(tracks, startIndex: 4);

    transport.emitTrackEnded();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(controller.isPlayingNotifier.value, isFalse);
    expect(controller.currentIndexNotifier.value, 4);

    transport.resetCalls();
    await controller.previous();

    expect(controller.currentIndexNotifier.value, 4);
    expect(controller.isPlayingNotifier.value, isTrue);
    expect(transport.loadedPath, '/path/track_4.mp3');
    expect(transport.seekCalls, contains(Duration.zero));
  });

  test('shuffleQueue() keeps current track playing without restart', () async {
    final tracks = createTracks(5);
    await controller.setQueue(tracks, startIndex: 0);
    expect(controller.isPlayingNotifier.value, isTrue);
    expect(transport.loadedPath, '/path/track_0.mp3');

    transport.resetCalls();
    await controller.shuffleQueue();

    expect(controller.isPlayingNotifier.value, isTrue);
    final currentIndex = controller.currentIndexNotifier.value;
    expect(currentIndex, isNotNull);
    final currentTrackPath = controller.queueNotifier.value[currentIndex!].path;
    expect(currentTrackPath, '/path/track_0.mp3');
    expect(transport.loadedPath, '/path/track_0.mp3');
    expect(transport.loadCalls, isEmpty);
  });
}
