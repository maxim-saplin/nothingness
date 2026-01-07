import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import 'mock_audio_transport.dart';

class MockPlaylistStore extends PlaylistStore {
  final List<AudioTrack> _tracks = [];
  int? _currentIndex;

  @override
  int get length => _tracks.length;

  @override
  int get baseLength => _tracks.length;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startBaseIndex = 0,
    bool enableShuffle = false,
  }) async {
    _tracks.clear();
    _tracks.addAll(tracks);
    _currentIndex = startBaseIndex;
    queueNotifier.value = List.from(_tracks);
    currentOrderIndexNotifier.value = _currentIndex;
  }

  @override
  Future<void> setCurrentOrderIndex(int orderIndex) async {
    _currentIndex = orderIndex;
    currentOrderIndexNotifier.value = orderIndex;
    // Return immediately (synchronous future)
    return Future.value();
  }

  @override
  AudioTrack? trackForOrderIndex(int orderIndex) {
    if (orderIndex >= 0 && orderIndex < _tracks.length) {
      return _tracks[orderIndex];
    }
    return null;
  }

  @override
  int? nextOrderIndex() {
    if (_currentIndex == null) return null;
    if (_currentIndex! + 1 < _tracks.length) return _currentIndex! + 1;
    return null;
  }
  
  @override
  int? orderIndexForBase(int baseIndex) => baseIndex;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MockAudioTransport transport;
  late MockPlaylistStore playlist;
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
    tempDir = await Directory.systemTemp.createTemp('playback_skip_bug_$testNumber');
    Hive.init(tempDir.path);

    transport = MockAudioTransport();
    playlist = MockPlaylistStore();

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
      if (Hive.isBoxOpen('playlistBox_skip_$testNumber')) {
        await Hive.box('playlistBox_skip_$testNumber').close();
      }
    } catch (_) {}
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('reproduction: skips valid track after failing track', () async {
    // Setup: Track 0 (OK), Track 1 (Fail), Track 2 (OK)
    final tracks = createTracks(3);
    transport.pathsToFailOnLoad.add('/path/track_1.mp3');
    // Add a small delay to load to ensure race condition triggers
    transport.loadDelay = const Duration(milliseconds: 10);
    
    await controller.setQueue(tracks);
    
    // Start playing Track 0
    await controller.playFromQueueIndex(0);
    expect(controller.currentIndexNotifier.value, 0);
    expect(controller.isPlayingNotifier.value, true);
    expect(controller.userIntent, PlayIntent.play);

    // Simulate Track 0 ending
    transport.emitTrackEnded();

    // Wait for async chains to complete
    // The chain is: 
    // 1. handleTrackEnded -> _skipToNext -> playFromQueueIndex(1)
    // 2. playFromQueueIndex(1) -> load -> error -> handleTrackError -> _skipToNext -> playFromQueueIndex(2)
    // 3. playFromQueueIndex(2) -> load -> play
    
    // We need to give enough time for all microtasks and timers
    await Future.delayed(const Duration(milliseconds: 100));

    // Expectation: Should be playing Track 2
    expect(controller.currentIndexNotifier.value, 2, reason: 'Should have skipped to Track 2');
    
    // This is the bug: isPlayingNotifier might be false
    expect(controller.isPlayingNotifier.value, true, reason: 'Should be playing Track 2');
    
    // Also check if transport is actually playing
    expect(transport.isPlaying, true, reason: 'Transport should be playing');
  });
}
