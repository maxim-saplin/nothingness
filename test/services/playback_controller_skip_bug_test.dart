import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import '../support/pump_until.dart';
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
    );
    await controller.init();
  });

  tearDown(() async {
    await controller.shutdown();
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
    
    // Wait for the error → skip → load → play chain to fully settle on Track 2.
    // The index commits before load()+play(); also wait for the transport to be
    // actually playing (this test has a loadDelay) before asserting on it.
    await pumpUntil(() =>
        controller.currentIndexNotifier.value == 2 && transport.isPlaying);

    // Expectation: Should be playing Track 2
    expect(controller.currentIndexNotifier.value, 2, reason: 'Should have skipped to Track 2');
    
    // This is the bug: isPlayingNotifier might be false
    expect(controller.isPlayingNotifier.value, true, reason: 'Should be playing Track 2');
    
    // Also check if transport is actually playing
    expect(transport.isPlaying, true, reason: 'Transport should be playing');
  });

  test('B-036: duplicate ended during an in-flight advance does not skip a track',
      () async {
    final tracks = createTracks(4);
    // Keep the advance in load() long enough that the duplicate `ended`
    // deterministically arrives *while the first advance is still in flight* —
    // that is the real B-036 race (a 300 ms poll + a `soundEvents` notification
    // for the same track). A wide window removes timing luck from the test.
    transport.loadDelay = const Duration(milliseconds: 80);

    await controller.setQueue(tracks);
    await pumpUntil(() => controller.currentIndexNotifier.value == 0);

    // Track 0 ends → the advance to track 1 begins and parks in load().
    transport.emitTrackEnded();
    // The advance commits the index to 1 (set before load) while still loading.
    await pumpUntil(() => controller.currentIndexNotifier.value == 1);

    // Duplicate/stale ended arrives mid-advance. The guard must ignore it;
    // without it, `_handleTrackEnded` advances again from the current index
    // (1 → 2), loading and skipping track 1 before it ever plays.
    transport.emitTrackEnded();

    // Let the single legitimate advance finish, then give any erroneous second
    // advance its full chance to manifest before asserting it never happened
    // (a "did NOT skip" check needs a settle window, not a positive pumpUntil).
    await pumpUntil(() => controller.isPlayingNotifier.value &&
        controller.currentIndexNotifier.value == 1);
    await Future.delayed(const Duration(milliseconds: 150));

    expect(controller.currentIndexNotifier.value, 1,
        reason: 'duplicate ended must not skip track 1');
    expect(transport.loadCalls, isNot(contains('/path/track_2.mp3')),
        reason: 'no second advance should have loaded track 2');

    // A genuine later end still advances normally (guard is cleared).
    transport.emitTrackEnded();
    await pumpUntil(() => controller.currentIndexNotifier.value == 2);
    expect(controller.currentIndexNotifier.value, 2,
        reason: 'a real later ended still advances');
  });

  test('B-037: controller preloads the upcoming track after play', () async {
    final tracks = createTracks(3);
    await controller.setQueue(tracks);
    // After starting track 0, the next track (track 1) should be preloaded.
    await pumpUntil(() => transport.preloadCalls.contains('/path/track_1.mp3'));
    expect(transport.preloadCalls, contains('/path/track_1.mp3'),
        reason: 'Should look ahead and preload the next track');

    // Advance; now track 2 should become the preload target.
    transport.emitTrackEnded();
    await pumpUntil(() => transport.preloadCalls.contains('/path/track_2.mp3'));
    expect(controller.currentIndexNotifier.value, 1);
    expect(transport.preloadCalls, contains('/path/track_2.mp3'));
  });

  test('B-048: a burst of next() taps advances per-tap but loads once',
      () async {
    final tracks = createTracks(6);
    transport.loadDelay = const Duration(milliseconds: 10);
    await controller.setQueue(tracks);
    await pumpUntil(() => controller.currentIndexNotifier.value == 0);

    transport.loadCalls.clear();

    // Five rapid taps, as a fast finger would (the first four un-awaited). Each
    // tap advances the index immediately; the heavy load is debounced so the
    // whole burst loads only the track we land on — no per-tap decode pile-up.
    controller.next();
    controller.next();
    controller.next();
    controller.next();
    await controller.next();
    await pumpUntil(() => controller.isPlayingNotifier.value &&
        controller.currentIndexNotifier.value == 5);

    // Per-tap advance: 5 taps from index 0 → index 5.
    expect(controller.currentIndexNotifier.value, 5,
        reason: 'each tap advances the index immediately');
    // Debounced: the burst loads only the landed track, not every intermediate.
    expect(transport.loadCalls, ['/path/track_5.mp3'],
        reason: 'one load for the whole burst (the track we land on)');
    expect(controller.isPlayingNotifier.value, true);
  });

  test('B-037: no preload at the queue tail', () async {
    final tracks = createTracks(2);
    await controller.setQueue(tracks);
    await pumpUntil(() => controller.currentIndexNotifier.value == 0);
    // setQueue auto-plays index 0 (which preloads index 1); isolate the
    // tail-play behaviour by clearing that first.
    transport.preloadCalls.clear();

    await controller.playFromQueueIndex(1); // last track
    // Negative assertion: give a would-be preload its chance, then confirm none.
    await Future.delayed(const Duration(milliseconds: 30));

    expect(transport.preloadCalls, isEmpty,
        reason: 'Nothing to preload past the tail');
  });
}
