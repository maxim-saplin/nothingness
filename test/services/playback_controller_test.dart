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

  List<AudioTrack> createTracks(int count, {int startAt = 0}) {
    return List.generate(
      count,
      (i) => AudioTrack(
        path: '/path/track_${startAt + i}.mp3',
        title: 'Track ${startAt + i}',
      ),
    );
  }

  setUp(() async {
    testNumber++;
    tempDir = await Directory.systemTemp.createTemp('playback_controller_test_$testNumber');
    Hive.init(tempDir.path);

    transport = MockAudioTransport();
    playlist = PlaylistStore(
      hive: Hive,
      hiveInitializer: () async {},
      boxOpener: (hive) => hive.openBox<dynamic>('playlistBox_$testNumber'),
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
    // Close only the box we opened, not all boxes
    try {
      if (Hive.isBoxOpen('playlistBox_$testNumber')) {
        await Hive.box('playlistBox_$testNumber').close();
      }
    } catch (_) {}
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ===========================================================================
  // GROUP: Initial State
  // ===========================================================================
  group('Initial State', () {
    test('starts with userIntent=pause', () {
      expect(controller.userIntent, PlayIntent.pause);
    });

    test('starts with isPlaying=false', () {
      expect(controller.isPlayingNotifier.value, false);
    });

    test('starts with empty queue', () {
      expect(controller.queueNotifier.value, isEmpty);
    });

    test('starts with null currentIndex', () {
      expect(controller.currentIndexNotifier.value, isNull);
    });
  });

  // ===========================================================================
  // GROUP: setQueue Behavior
  // ===========================================================================
  group('setQueue', () {
    test('populates queue and starts playback', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks);

      expect(controller.queueNotifier.value.length, 3);
      expect(controller.userIntent, PlayIntent.play);
      expect(controller.isPlayingNotifier.value, true);
      expect(transport.loadCalls, hasLength(1));
      expect(transport.playCalls, hasLength(1));
    });

    test('clears isNotFound flags from previous queue', () async {
      // First queue with a failing track
      transport.pathsToFailOnLoad.add('/path/track_0.mp3');
      final tracks1 = createTracks(2);
      await controller.setQueue(tracks1);

      // Track 0 should be marked as not found
      expect(
        controller.queueNotifier.value[0].isNotFound,
        true,
        reason: 'Track should be marked as not found after load failure',
      );

      // Set a new queue - should clear the not found state
      transport.pathsToFailOnLoad.clear();
      final tracks2 = createTracks(2, startAt: 10);
      await controller.setQueue(tracks2);

      expect(
        controller.queueNotifier.value.every((t) => !t.isNotFound),
        true,
        reason: 'New queue should not have any isNotFound flags',
      );
    });

    test('respects startIndex parameter', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks, startIndex: 2);

      expect(controller.currentIndexNotifier.value, 2);
      expect(transport.loadCalls.last, '/path/track_2.mp3');
    });
  });

  // ===========================================================================
  // GROUP: playPause Behavior
  // ===========================================================================
  group('playPause', () {
    test('toggles from pause to play', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks);
      
      // Currently playing, pause it
      await controller.playPause();
      expect(controller.userIntent, PlayIntent.pause);
      expect(controller.isPlayingNotifier.value, false);
      expect(transport.pauseCalls, hasLength(1));

      // Now play again
      transport.resetCalls();
      await controller.playPause();
      expect(controller.userIntent, PlayIntent.play);
      expect(controller.isPlayingNotifier.value, true);
      expect(transport.playCalls, hasLength(1));
    });

    test('starts playback if nothing loaded yet', () async {
      // Add tracks to the queue via addTracks without auto-play
      final tracks = createTracks(3);
      await controller.addTracks(tracks, play: false);

      // Now playPause should start playback
      await controller.playPause();

      expect(controller.userIntent, PlayIntent.play);
      // Load is called when we try to play
      expect(transport.loadCalls, isNotEmpty);
    });

    test('does nothing on empty queue', () async {
      await controller.playPause();

      expect(controller.userIntent, PlayIntent.pause);
      expect(transport.loadCalls, isEmpty);
      expect(transport.playCalls, isEmpty);
    });
  });

  // ===========================================================================
  // GROUP: User Intent Tracking
  // ===========================================================================
  group('User Intent', () {
    test('next() sets userIntent=play', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks);
      await controller.playPause(); // pause
      expect(controller.userIntent, PlayIntent.pause);

      await controller.next();
      expect(controller.userIntent, PlayIntent.play);
    });

    test('previous() sets userIntent=play', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks, startIndex: 2);
      await controller.playPause(); // pause
      expect(controller.userIntent, PlayIntent.pause);

      await controller.previous();
      expect(controller.userIntent, PlayIntent.play);
    });

    test('playFromQueueIndex sets userIntent=play for valid tracks', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks);
      await controller.playPause(); // pause
      expect(controller.userIntent, PlayIntent.pause);

      await controller.playFromQueueIndex(3);
      expect(controller.userIntent, PlayIntent.play);
    });

    test('pause intent is respected during load', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks);

      // Simulate: user pauses while a track is loading
      // This is a race condition scenario
      controller.playPause(); // Start pause
      
      // The controller should check userIntent after load completes
      expect(controller.userIntent, PlayIntent.pause);
    });
  });

  // ===========================================================================
  // GROUP: Error Recovery (isNotFound)
  // ===========================================================================
  group('Error Recovery', () {
    test('marks track as isNotFound on load failure', () async {
      transport.pathsToFailOnLoad.add('/path/track_0.mp3');
      final tracks = createTracks(3);

      await controller.setQueue(tracks);
      // Allow async event handlers to process
      await Future.delayed(const Duration(milliseconds: 50));

      // First track should be marked as not found
      final queue = controller.queueNotifier.value;
      expect(queue[0].isNotFound, true);
      expect(queue[0].title, 'Track 0');
    });

    test('skips to next track on error when userIntent=play', () async {
      transport.pathsToFailOnLoad.add('/path/track_0.mp3');
      final tracks = createTracks(3);

      await controller.setQueue(tracks);
      // Allow async event handlers to process the error and skip
      await Future.delayed(const Duration(milliseconds: 50));

      // Should have skipped to track 1
      expect(controller.currentIndexNotifier.value, 1);
      expect(transport.loadCalls, contains('/path/track_1.mp3'));
    });

    test('stays paused on error when userIntent=pause', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks);
      await controller.playPause(); // pause
      expect(controller.userIntent, PlayIntent.pause);

      // Simulate error on current track
      transport.emitError('/path/track_0.mp3', Exception('File removed'));
      await Future.delayed(const Duration(milliseconds: 50));

      // Should stay paused, not skip
      expect(controller.isPlayingNotifier.value, false);
      // Note: currentIndex might still be 0 since we didn't skip
    });

    test('clears isNotFound on successful retry', () async {
      // Track fails initially
      transport.pathsToFailOnLoad.add('/path/track_0.mp3');
      final tracks = createTracks(3);
      await controller.setQueue(tracks);
      await Future.delayed(const Duration(milliseconds: 50));
      
      expect(controller.queueNotifier.value[0].isNotFound, true);

      // Now simulate: file is restored, user tries again
      transport.pathsToFailOnLoad.clear();
      transport.resetCalls();
      
      // Go back to track 0
      await controller.playFromQueueIndex(0);
      await Future.delayed(const Duration(milliseconds: 50));

      // Track should no longer be marked as not found
      expect(
        controller.queueNotifier.value[0].isNotFound,
        false,
        reason: 'isNotFound should clear on successful load',
      );
    });

    test('stops gracefully when all tracks fail', () async {
      // All tracks will fail
      transport.pathsToFailOnLoad.addAll([
        '/path/track_0.mp3',
        '/path/track_1.mp3',
        '/path/track_2.mp3',
      ]);
      final tracks = createTracks(3);

      await controller.setQueue(tracks);
      // Allow async error handling chain to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // All tracks should be marked as not found
      expect(controller.queueNotifier.value.every((t) => t.isNotFound), true);
      
      // Playback should have stopped (no infinite loop)
      expect(controller.isPlayingNotifier.value, false);
    });

    test('does not auto-play known broken track on tap', () async {
      transport.pathsToFailOnLoad.add('/path/track_1.mp3');
      final tracks = createTracks(3);
      await controller.setQueue(tracks);
      await Future.delayed(const Duration(milliseconds: 50));

      // First, reach track 1 via Next so it becomes known-failed.
      await controller.next(); // tries track 1, fails, advances to 2
      await Future.delayed(const Duration(milliseconds: 80));

      expect(controller.queueNotifier.value[1].isNotFound, true);
      expect(controller.currentIndexNotifier.value, 2);
      expect(controller.isPlayingNotifier.value, true);

      // User taps on track 1 in the queue: should mark red and advance to a
      // playable track (track 2), keeping playback running.
      transport.resetCalls();
      await controller.playFromQueueIndex(1);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.queueNotifier.value[1].isNotFound, true);
      expect(controller.currentIndexNotifier.value, 2);
      expect(controller.isPlayingNotifier.value, true);
    });

    test('previous() skips known missing track and keeps playback running', () async {
      // Start at track 3, but track 2 is missing.
      transport.pathsToFailOnLoad.add('/path/track_2.mp3');
      final tracks = createTracks(5);
      await controller.setQueue(tracks, startIndex: 3);
      await Future.delayed(const Duration(milliseconds: 50));

      // Going previous should attempt track 2, mark it not found, then land on 1.
      await controller.previous();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(controller.queueNotifier.value[2].isNotFound, true);
      expect(controller.currentIndexNotifier.value, 1);
      expect(controller.isPlayingNotifier.value, true);
    });

    test('skips missing track then plays next available', () async {
      // track 2 (index 2) is missing; start from track 1
      transport.pathsToFailOnLoad.add('/path/track_2.mp3');
      final tracks = createTracks(5);

      await controller.setQueue(tracks, startIndex: 1);
      await Future.delayed(const Duration(milliseconds: 30));

      // Simulate natural end of track 1
      transport.emitTrackEnded();
      await Future.delayed(const Duration(milliseconds: 80));

      // Should mark track 2 as not found and land on track 3 playing
      expect(controller.currentIndexNotifier.value, 3);
      expect(controller.queueNotifier.value[2].isNotFound, true);
      expect(controller.queueNotifier.value[3].isNotFound, false);
      expect(controller.isPlayingNotifier.value, true);

      // Ensure we did NOT skip past track 3
      expect(transport.loadCalls, contains('/path/track_3.mp3'));
      expect(transport.loadCalls, isNot(contains('/path/track_4.mp3')));
    });

    // Regression test for double-skip bug:
    // When track 0 fails, error handler calls _skipToNext() which loads track 1.
    // But the original playFromQueueIndex(0) call's aftermath was incorrectly
    // setting isPlayingNotifier.value = false, pausing track 1.
    test('auto-skip to next track keeps playback running (no double-skip)', () async {
      // Only track 0 fails, tracks 1 and 2 are valid
      transport.pathsToFailOnLoad.add('/path/track_0.mp3');
      final tracks = createTracks(3);

      await controller.setQueue(tracks);
      // Allow async error handling to complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Should have skipped to track 1 and be PLAYING
      expect(
        controller.currentIndexNotifier.value,
        1,
        reason: 'Should skip to track 1 after track 0 fails',
      );
      expect(
        controller.isPlayingNotifier.value,
        true,
        reason: 'Track 1 should be playing after auto-skip from failed track 0',
      );
      expect(
        controller.userIntent,
        PlayIntent.play,
        reason: 'User intent should remain play after auto-skip',
      );

      // Verify track 1 was loaded (not track 2 - no double skip)
      expect(
        transport.loadCalls.last,
        '/path/track_1.mp3',
        reason: 'Should have loaded track 1, not skipped further',
      );
      
      // Track 1 should NOT be marked as not found
      expect(
        controller.queueNotifier.value[1].isNotFound,
        false,
        reason: 'Track 1 should not be marked as not found',
      );
    });

    // More precise test: simulate async timing where error event fires after load
    // returns but before play() is called. This catches the case where the
    // original playFromQueueIndex continuation corrupts state.
    test('auto-skip preserves play state when error fires asynchronously', () async {
      // Track 0 fails, track 1 is valid
      transport.pathsToFailOnLoad.add('/path/track_0.mp3');
      // Add load delay to simulate real async behavior
      transport.loadDelay = const Duration(milliseconds: 10);
      final tracks = createTracks(3);

      await controller.setQueue(tracks);
      // Give more time for async error chain to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Should be on track 1, playing
      expect(
        controller.currentIndexNotifier.value,
        1,
        reason: 'Should have auto-skipped to track 1',
      );
      expect(
        controller.isPlayingNotifier.value,
        true,
        reason: 'Should be playing track 1 after auto-skip',
      );
      
      // Verify play was called for track 1
      expect(
        transport.playCalls.where((p) => p == '/path/track_1.mp3').length,
        greaterThan(0),
        reason: 'play() should have been called for track 1',
      );
    });

    // Test for delayed/duplicate error events from the transport's error stream.
    // In real transports, errors can fire from multiple sources or be delayed.
    // This should NOT cause the valid track to be marked as failed.
    test('delayed duplicate error event does not corrupt next track', () async {
      // Track 0 fails, track 1 is valid
      transport.pathsToFailOnLoad.add('/path/track_0.mp3');
      final tracks = createTracks(3);

      await controller.setQueue(tracks);
      await Future.delayed(const Duration(milliseconds: 50));

      // Should be on track 1, playing
      expect(controller.currentIndexNotifier.value, 1);
      expect(controller.isPlayingNotifier.value, true);

      // Simulate a delayed/duplicate error event for track 0's path
      // This could happen in real transports where errorStream fires after load() returns
      transport.emitError('/path/track_0.mp3', Exception('Delayed error'));
      await Future.delayed(const Duration(milliseconds: 50));

      // Track 1 should STILL be playing - the delayed error for track 0
      // should not affect the current track (track 1)
      expect(
        controller.currentIndexNotifier.value,
        1,
        reason: 'Current track should still be track 1',
      );
      expect(
        controller.isPlayingNotifier.value,
        true,
        reason: 'Track 1 should still be playing after delayed error for track 0',
      );
      expect(
        controller.queueNotifier.value[1].isNotFound,
        false,
        reason: 'Track 1 should NOT be marked as not found',
      );
    });

    // Regression test: Real transports may emit error with CURRENT path (not failed path)
    // when the errorStream fires after we've already moved to the next track.
    // This simulates: track 0 ends → track 1 fails → skip to track 2 →
    // errorStream fires with _currentPath (now track 2) → track 2 incorrectly marked failed
    test('error event with wrong path does not mark valid track as failed', () async {
      // Track 1 fails, tracks 0 and 2 are valid
      transport.pathsToFailOnLoad.add('/path/track_1.mp3');
      final tracks = createTracks(4);

      await controller.setQueue(tracks);
      await Future.delayed(const Duration(milliseconds: 50));

      // Should be on track 0, playing
      expect(controller.currentIndexNotifier.value, 0);
      expect(controller.isPlayingNotifier.value, true);

      // Simulate track 0 ending naturally
      transport.emitTrackEnded();
      await Future.delayed(const Duration(milliseconds: 50));

      // Should have skipped track 1 (failed) and be on track 2, playing
      expect(
        controller.currentIndexNotifier.value,
        2,
        reason: 'Should have skipped track 1 and be on track 2',
      );
      expect(controller.isPlayingNotifier.value, true);

      // Simulate the transport's errorStream firing with the CURRENT path
      // (this is what happens in real transports - errorStream uses _currentPath)
      transport.emitError('/path/track_2.mp3', Exception('Spurious error with wrong path'));
      await Future.delayed(const Duration(milliseconds: 50));

      // Track 2 should NOT be marked as failed - it loaded successfully!
      // The error event had the wrong path (track 2's path instead of track 1's)
      expect(
        controller.queueNotifier.value[2].isNotFound,
        false,
        reason: 'Track 2 should NOT be marked as not found - it loaded successfully',
      );
      // Should still be playing track 2
      expect(
        controller.currentIndexNotifier.value,
        2,
        reason: 'Should still be on track 2',
      );
      expect(
        controller.isPlayingNotifier.value,
        true,
        reason: 'Track 2 should still be playing',
      );
    });

    // Regression test: When track 3 fails and we skip to track 4, track 3's
    // error event may be processed AFTER we've moved to track 4.
    // Track 3 should still be marked as "not found" even though we've moved on.
    test('delayed error for skipped track still marks it as failed', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks);
      await Future.delayed(const Duration(milliseconds: 50));

      // Start at track 0
      expect(controller.currentIndexNotifier.value, 0);

      // Advance to track 2 (simulating track 1 ending and going to 2)
      await controller.playFromQueueIndex(2);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.currentIndexNotifier.value, 2);

      // Simulate a delayed error event for track 1 (which we already passed)
      // This shouldn't affect current playback but SHOULD mark track 1 as failed
      // Actually wait - in this scenario track 1 never failed, so we shouldn't mark it
      // Let's do the real scenario: track 2 ends, track 3 fails, skip to 4
      
      // Set up track 3 to fail
      transport.pathsToFailOnLoad.add('/path/track_3.mp3');
      
      // Advance from track 2 - will try track 3, fail, skip to track 4
      transport.emitTrackEnded();
      await Future.delayed(const Duration(milliseconds: 100));

      // Should be on track 4
      expect(
        controller.currentIndexNotifier.value,
        4,
        reason: 'Should have skipped track 3 and be on track 4',
      );
      expect(
        controller.isPlayingNotifier.value,
        true,
        reason: 'Track 4 should be playing',
      );
      
      // Track 3 SHOULD be marked as not found
      expect(
        controller.queueNotifier.value[3].isNotFound,
        true,
        reason: 'Track 3 should be marked as not found',
      );
      
      // Track 4 should NOT be marked as not found
      expect(
        controller.queueNotifier.value[4].isNotFound,
        false,
        reason: 'Track 4 should NOT be marked as not found',
      );
    });

    test('error during auto-skip does not corrupt state of subsequent track', () async {
      // Track 0 fails, track 1 is valid
      transport.pathsToFailOnLoad.add('/path/track_0.mp3');
      final tracks = createTracks(3);

      await controller.setQueue(tracks);
      await Future.delayed(const Duration(milliseconds: 50));

      // Reset call tracking to see what happens when we click next
      transport.resetCalls();
      
      // Now explicitly go to track 2
      await controller.next();
      await Future.delayed(const Duration(milliseconds: 50));

      // Should be on track 2 and playing
      expect(controller.currentIndexNotifier.value, 2);
      expect(controller.isPlayingNotifier.value, true);
      expect(transport.loadCalls, contains('/path/track_2.mp3'));
    });

    test('repro: late error event with current path does not skip valid track', () async {
      // Setup: Tracks 1, 2, 3, 4, 5
      // Track 3 is missing/fails to load
      final tracks = createTracks(5, startAt: 1);
      transport.pathsToFailOnLoad.add('/path/track_3.mp3');
      
      await controller.setQueue(tracks);
      
      // Start playing Track 2
      await controller.playFromQueueIndex(1);
      await Future.delayed(const Duration(milliseconds: 50));
      
      expect(controller.currentIndexNotifier.value, 1, reason: 'Should be on Track 2');
      expect(controller.isPlayingNotifier.value, true, reason: 'Track 2 should be playing');

      // Simulate Track 2 ending naturally
      // This triggers: Load Track 3 -> Fail -> Skip -> Load Track 4
      transport.emitTrackEnded();
      
      // Allow async operations to complete (load failure, skip, load success)
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify we are now on Track 4
      expect(controller.currentIndexNotifier.value, 3, reason: 'Should have skipped Track 3 and be on Track 4');
      expect(controller.isPlayingNotifier.value, true, reason: 'Track 4 should be playing');
      expect(transport.loadedPath, '/path/track_4.mp3', reason: 'Transport should have loaded Track 4');
      
      // Verify Track 3 is marked as failed
      expect(controller.queueNotifier.value[2].isNotFound, true, reason: 'Track 3 should be marked as not found');
      
      // Verify Track 4 is NOT marked as failed
      expect(controller.queueNotifier.value[3].isNotFound, false, reason: 'Track 4 should be valid');

      // SIMULATE THE BUG CONDITION:
      // Transport emits an error event, but it arrives late and is attributed to the CURRENT path (Track 4)
      // This happens in some transports where the error callback doesn't carry the original path
      // or simply fires after the internal state has updated.
      transport.emitError('/path/track_4.mp3', Exception('Late error from previous track'));
      
      await Future.delayed(const Duration(milliseconds: 50));

      // ASSERTIONS:
      // 1. We should STILL be on Track 4
      expect(controller.currentIndexNotifier.value, 3, reason: 'Should still be on Track 4 after spurious error');
      
      // 2. Track 4 should STILL be playing
      expect(controller.isPlayingNotifier.value, true, reason: 'Track 4 should still be playing');
      
      // 3. Track 4 should NOT be marked as failed
      expect(controller.queueNotifier.value[3].isNotFound, false, reason: 'Track 4 should NOT be marked as failed');
      
      // 4. We should NOT have skipped to Track 5
      expect(transport.loadCalls, isNot(contains('/path/track_5.mp3')), reason: 'Should not have attempted to load Track 5');
    });
  });

  // ===========================================================================
  // GROUP: Track Completion
  // ===========================================================================
  group('Track Completion', () {
    test('advances to next track when userIntent=play', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks);
      expect(controller.currentIndexNotifier.value, 0);

      // Simulate track ending
      transport.emitTrackEnded();

      // Allow async handlers to complete
      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.currentIndexNotifier.value, 1);
      expect(transport.loadCalls.last, '/path/track_1.mp3');
    });

    test('stops at end of queue', () async {
      final tracks = createTracks(2);
      await controller.setQueue(tracks, startIndex: 1); // Start at last track
      expect(controller.currentIndexNotifier.value, 1);

      transport.emitTrackEnded();
      await Future.delayed(const Duration(milliseconds: 50));

      // Should stop, not wrap around
      expect(controller.isPlayingNotifier.value, false);
    });

    test('does not advance when userIntent=pause', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks);
      await controller.playPause(); // pause
      expect(controller.userIntent, PlayIntent.pause);

      final indexBefore = controller.currentIndexNotifier.value;
      transport.emitTrackEnded();
      await Future.delayed(const Duration(milliseconds: 50));

      // Should not have advanced
      expect(controller.currentIndexNotifier.value, indexBefore);
      expect(controller.isPlayingNotifier.value, false);
    });
  });

  // ===========================================================================
  // GROUP: Shuffle/Unshuffle Behavior
  // ===========================================================================
  group('Shuffle', () {
    test('shuffleQueue preserves current play state', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks);
      await controller.playPause(); // pause

      final wasPlaying = controller.isPlayingNotifier.value;
      await controller.shuffleQueue();

      // Play state should be preserved (still paused)
      // Currently this FAILS because shuffleQueue calls playFromQueueIndex
      // which sets userIntent=play
      // 
      // EXPECTED: shuffleQueue should NOT change play/pause state
      expect(
        controller.isPlayingNotifier.value,
        wasPlaying,
        reason: 'Shuffle should not change play/pause state',
      );
    });

    test('disableShuffle preserves current play state', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks, shuffle: true);
      await controller.playPause(); // pause

      final wasPlaying = controller.isPlayingNotifier.value;
      await controller.disableShuffle();

      expect(
        controller.isPlayingNotifier.value,
        wasPlaying,
        reason: 'Disable shuffle should not change play/pause state',
      );
    });
  });

  // ===========================================================================
  // GROUP: Navigation (next/previous)
  // ===========================================================================
  group('Navigation', () {
    test('next() advances to next track', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks, startIndex: 0);

      await controller.next();

      expect(controller.currentIndexNotifier.value, 1);
    });

    test('next() at end of queue does nothing', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks, startIndex: 2);

      await controller.next();

      expect(controller.currentIndexNotifier.value, 2);
    });

    test('previous() goes to previous track', () async {
      final tracks = createTracks(5);
      await controller.setQueue(tracks, startIndex: 2);

      await controller.previous();

      expect(controller.currentIndexNotifier.value, 1);
    });

    test('previous() at start of queue does nothing', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks, startIndex: 0);

      await controller.previous();

      expect(controller.currentIndexNotifier.value, 0);
    });
  });

  // ===========================================================================
  // GROUP: playFromQueueIndex Edge Cases
  // ===========================================================================
  group('playFromQueueIndex', () {
    test('ignores invalid index (negative)', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks);
      transport.resetCalls();

      await controller.playFromQueueIndex(-1);

      expect(transport.loadCalls, isEmpty);
    });

    test('ignores invalid index (beyond queue)', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks);
      transport.resetCalls();

      await controller.playFromQueueIndex(10);

      expect(transport.loadCalls, isEmpty);
    });

    test('tapping current track toggles play/pause', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks, startIndex: 1);
      expect(controller.isPlayingNotifier.value, true);

      // Tap the same track that's currently playing
      await controller.playFromQueueIndex(1);

      // Should have toggled to pause (or stayed playing, depending on design)
      // Currently, playFromQueueIndex always sets userIntent=play and reloads
      // This might not be desired behavior
    });
  });

  // ===========================================================================
  // GROUP: Concurrent Operations (Race Conditions)  
  // ===========================================================================
  group('Concurrent Operations', () {
    test('rapid playPause calls stabilize correctly', () async {
      final tracks = createTracks(3);
      await controller.setQueue(tracks);

      // Rapid fire play/pause
      controller.playPause();
      controller.playPause();
      controller.playPause();
      await Future.delayed(const Duration(milliseconds: 50));

      // Final state should be consistent
      final intent = controller.userIntent;
      final isPlaying = controller.isPlayingNotifier.value;
      
      // They should match
      expect(
        isPlaying,
        intent == PlayIntent.play,
        reason: 'isPlaying should match userIntent after stabilization',
      );
    });

    test('pause during load cancels playback', () async {
      final tracks = createTracks(3);
      transport.autoEmitLoadedEvent = false; // Delay load completion
      
      // Start loading
      final loadFuture = controller.setQueue(tracks);
      
      // Immediately pause
      controller.playPause();
      
      // Complete the load
      transport.autoEmitLoadedEvent = true;
      await loadFuture;

      // Should respect the pause intent
      expect(controller.userIntent, PlayIntent.pause);
      expect(controller.isPlayingNotifier.value, false);
    });
  });
}
