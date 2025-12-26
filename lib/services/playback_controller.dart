import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/audio_track.dart';
import '../models/song_info.dart';
import 'audio_transport.dart';
import 'just_audio_transport.dart';
import 'playlist_store.dart';
import 'soloud_transport.dart';

/// Represents the user's explicit intent for playback state.
enum PlayIntent {
  /// User wants music to play
  play,

  /// User wants silence (paused)
  pause,
}

/// Single source of truth for playback logic.
/// Manages user intent, queue, error recovery, and coordinates with AudioTransport.
class PlaybackController {
  final AudioTransport _transport;
  final PlaylistStore _playlist;

  // User intent - explicit state for what the user wants
  PlayIntent _userIntent = PlayIntent.pause;
  PlayIntent get userIntent => _userIntent;

  // State notifiers
  final ValueNotifier<SongInfo?> songInfoNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);

  // Track paths of files that failed to load (backend-agnostic)
  final Set<String> _failedTrackPaths = <String>{};

  // Track the path that was last successfully loaded.
  // Used to filter out spurious error events for tracks that already loaded OK.
  String? _lastSuccessfullyLoadedPath;

  // Track the path currently being loaded (pending load completion).
  // Used to correctly attribute error events even if we've moved to another track.
  String? _pendingLoadPath;

  // Flag to suppress auto-skip during explicit user actions (like tapping a track)
  bool _suppressAutoSkip = false;

  StreamSubscription<TransportEvent>? _transportEventSub;
  Timer? _positionTimer;

  // Wrapper notifier that includes isNotFound flags
  final ValueNotifier<List<AudioTrack>> queueNotifier = ValueNotifier(const []);

  final Set<String> _supportedExtensions;

  PlaybackController({
    required AudioTransport transport,
    PlaylistStore? playlist,
  }) : _transport = transport,
       _playlist = playlist ?? PlaylistStore(),
       _supportedExtensions = _getSupportedExtensions(transport);

  // Expose playlist notifiers
  ValueNotifier<int?> get currentIndexNotifier =>
      _playlist.currentOrderIndexNotifier;
  ValueNotifier<bool> get shuffleNotifier => _playlist.shuffleNotifier;

  Future<void> init() async {
    await _playlist.init();
    await _transport.init();

    // Listen to transport events
    _transportEventSub = _transport.eventStream.listen(_handleTransportEvent);

    // Listen to playlist changes and update queue with isNotFound flags
    _playlist.queueNotifier.addListener(_updateQueueWithNotFoundFlags);
    _playlist.currentOrderIndexNotifier.addListener(_onIndexChanged);
    _playlist.shuffleNotifier.addListener(_onShuffleChanged);

    // Update song info periodically
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _emitSongInfo(),
    );

    // Sync initial state
    _updateQueueWithNotFoundFlags();

    // Load the current track if available so it's ready to play
    final currentIdx = _playlist.currentOrderIndexNotifier.value;
    if (currentIdx != null) {
      final track = _playlist.trackForOrderIndex(currentIdx);
      if (track != null) {
        try {
          await _transport.load(
            track.path,
            title: track.title,
            artist: track.artist,
          );
        } catch (e) {
          // Ignore load errors on startup - they will be handled if user tries to play
          debugPrint('Failed to load initial track: \$e');
        }
      }
    }

    await _emitSongInfo(force: true);
  }

  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _transportEventSub?.cancel();
    _playlist.queueNotifier.removeListener(_updateQueueWithNotFoundFlags);
    _playlist.currentOrderIndexNotifier.removeListener(_onIndexChanged);
    _playlist.shuffleNotifier.removeListener(_onShuffleChanged);
    await _transport.dispose();
    await _playlist.dispose();
  }

  void _onIndexChanged() {
    _updateQueueWithNotFoundFlags();
    _emitSongInfo();
  }

  void _onShuffleChanged() {
    _updateQueueWithNotFoundFlags();
  }

  void _handleTransportEvent(TransportEvent event) {
    switch (event) {
      case TransportErrorEvent(:final path):
        _handleTrackError(path);
      case TransportEndedEvent(:final path):
        _handleTrackEnded(path);
      case TransportLoadedEvent(:final path):
        _onTrackLoaded(path);
      case TransportPositionEvent():
        // Position updates handled by timer
        break;
    }
  }

  void _handleTrackError(String? path) {
    if (path == null) return;

    // Ignore spurious error events for tracks that have already loaded successfully.
    // This can happen when the transport's errorStream fires with _currentPath
    // after we've already received a successful TransportLoadedEvent.
    if (path == _lastSuccessfullyLoadedPath) {
      return;
    }

    // Check if this error is for the path we were trying to load.
    // This handles the case where:
    // 1. We try to load track 3 → fails
    // 2. Error handler triggers skip to track 4 → loads successfully  
    // 3. Original error event for track 3 is processed
    // At step 3, currentTrack is track 4, but the error is for track 3.
    // We should still mark track 3 as failed.
    final isForPendingLoad = path == _pendingLoadPath;
    
    // Also check if error is for the current track (handles immediate errors)
    final currentIdx = _playlist.currentOrderIndexNotifier.value;
    final currentTrack = currentIdx == null
        ? null
        : _playlist.trackForOrderIndex(currentIdx);
    final isForCurrentTrack = currentTrack != null && currentTrack.path == path;
    
    if (!isForPendingLoad && !isForCurrentTrack) {
      // Error is for a completely different track - ignore it
      return;
    }

    // Mark the failing path as not found
    _failedTrackPaths.add(path);
    _updateQueueWithNotFoundFlags();
    
    // Clear pending if this error matches it
    if (_pendingLoadPath == path) {
      _pendingLoadPath = null;
    }

    // Skip only if the error is for the CURRENT track (avoid double skip when we already moved on)
    if (isForCurrentTrack) {
      if (_userIntent == PlayIntent.play && !_suppressAutoSkip) {
        _skipToNext();
      } else {
        isPlayingNotifier.value = false;
      }
    }
    // If the error was for a pending (previous) load but we've already moved to another track,
    // do not skip again.
  }

  void _handleTrackEnded(String? path) {
    // Advance to next track if user wants to play
    if (_userIntent == PlayIntent.play) {
      _skipToNext();
    } else {
      isPlayingNotifier.value = false;
    }
  }

  void _onTrackLoaded(String? path) {
    if (path == null) return;
    // Track this as successfully loaded to filter spurious error events
    _lastSuccessfullyLoadedPath = path;
    // Clear pending load path since load succeeded
    if (_pendingLoadPath == path) {
      _pendingLoadPath = null;
    }
    // Clear the failed flag if track now loads successfully
    if (_failedTrackPaths.remove(path)) {
      _updateQueueWithNotFoundFlags();
    }
    _emitSongInfo(force: true);
  }

  Future<void> _skipToNext() async {
    final nextIdx = _playlist.nextOrderIndex();
    if (nextIdx != null) {
      await playFromQueueIndex(nextIdx, isAutoSkip: true);
    } else {
      // End of queue
      isPlayingNotifier.value = false;
      await _transport.pause();
      _emitSongInfo(force: true);
    }
  }

  List<AudioTrack> _getQueueWithNotFoundFlags() {
    return _playlist.queueNotifier.value.map((track) {
      if (_failedTrackPaths.contains(track.path)) {
        return track.copyWith(isNotFound: true);
      }
      return track;
    }).toList();
  }

  void _updateQueueWithNotFoundFlags() {
    queueNotifier.value = _getQueueWithNotFoundFlags();
  }

  Future<void> playPause() async {
    if (_playlist.length == 0) return;

    // If nothing is loaded, start playback from current index
    final currentIdx = _playlist.currentOrderIndexNotifier.value;
    if (currentIdx == null) {
      final idx = _playlist.length > 0 ? 0 : null;
      if (idx != null) {
        await playFromQueueIndex(idx, isAutoSkip: true);
      }
      return;
    }

    // Toggle based on user intent (source of truth)
    if (_userIntent == PlayIntent.play) {
      // User wants to pause
      _userIntent = PlayIntent.pause;
      isPlayingNotifier.value = false; // Optimistic update
      await _transport.pause();
    } else {
      // User wants to play
      _userIntent = PlayIntent.play;
      isPlayingNotifier.value = true; // Optimistic update
      await _transport.play();

      // Correction: if intent changed to pause while we were starting playback
      if (_userIntent == PlayIntent.pause) {
        await _transport.pause();
        isPlayingNotifier.value = false;
      }
    }
    _emitSongInfo();
  }

  Future<void> next() async {
    _userIntent = PlayIntent.play; // Navigation implies play intent
    final nextIdx = _playlist.nextOrderIndex();
    if (nextIdx != null) {
      await playFromQueueIndex(nextIdx, isAutoSkip: true);
    }
  }

  Future<void> previous() async {
    _userIntent = PlayIntent.play; // Navigation implies play intent
    final prevIdx = _playlist.previousOrderIndex();
    if (prevIdx != null) {
      await playFromQueueIndex(prevIdx, isAutoSkip: true);
    }
  }

  Future<void> playFromQueueIndex(
    int orderIndex, {
    bool isAutoSkip = false,
    bool respectPauseIntent = false,
  }) async {
    if (orderIndex < 0 || orderIndex >= _playlist.length) return;

    final track = _playlist.trackForOrderIndex(orderIndex);
    if (track == null) return;

    // If track is known to be broken and this is an auto-skip (not user tap),
    // don't try to play - just select it
    if (isAutoSkip && _failedTrackPaths.contains(track.path)) {
      await _playlist.setCurrentOrderIndex(orderIndex);
      if (isPlayingNotifier.value) {
        await _transport.pause();
        isPlayingNotifier.value = false;
      }
      _emitSongInfo(force: true);
      return;
    }

    // If caller wants to respect pause intent (e.g., setQueue), check before proceeding
    if (respectPauseIntent && _userIntent == PlayIntent.pause) {
      await _playlist.setCurrentOrderIndex(orderIndex);
      isPlayingNotifier.value = false;
      _emitSongInfo(force: true);
      return;
    }

    // Save previous intent - we'll only commit to play intent if load succeeds
    await _playlist.setCurrentOrderIndex(orderIndex);

    // Optimistic update for UI responsiveness
    isPlayingNotifier.value = true;

    // Suppress auto-skip only for pure user taps (no special flags set)
    // When user explicitly taps a track and it fails, we don't want to auto-skip
    // Internal calls (setQueue, next, previous, etc.) should pass a flag to allow skip
    final isUserTap = !isAutoSkip && !respectPauseIntent;
    if (isUserTap) {
      _suppressAutoSkip = true;
    }

    // Track this as pending load - error handler will check this
    _pendingLoadPath = track.path;

    try {
      await _transport.load(
        track.path,
        title: track.title,
        artist: track.artist,
      );

      // Clear pending load path on success
      _pendingLoadPath = null;

      // Re-enable auto-skip
      if (isUserTap) {
        _suppressAutoSkip = false;
      }

      // Allow any error events to finish processing
      await Future<void>.delayed(Duration.zero);

      // Check if track failed to load (error handler may have added it)
      if (_failedTrackPaths.contains(track.path)) {
        // Keep pause intent, don't play
        if (_playlist.currentOrderIndexNotifier.value == orderIndex) {
          isPlayingNotifier.value = false;
        }
        return;
      }

      // Load succeeded - commit to play intent
      _userIntent = PlayIntent.play;

      await _transport.play();

      // Check again if user paused while starting playback
      if (_userIntent == PlayIntent.pause) {
        await _transport.pause();
        isPlayingNotifier.value = false;
      }
    } catch (e) {
      if (isUserTap) {
        _suppressAutoSkip = false;
      }
      // Treat thrown load errors as a failure of this track even if
      // the transport does not emit a well-formed error event.
      _failedTrackPaths.add(track.path);
      _pendingLoadPath = null;
      _updateQueueWithNotFoundFlags();
      debugPrint('Error playing track: $e');
      // Revert visual state on error
      isPlayingNotifier.value = false;
    }

    _emitSongInfo(force: true);
  }

  Future<void> seek(Duration position) async {
    await _transport.seek(position);
    _emitSongInfo();
  }

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    // Clear failed tracks when setting new queue
    _failedTrackPaths.clear();

    // Set intent to play BEFORE any await so concurrent playPause can cancel it
    if (tracks.isNotEmpty) {
      _userIntent = PlayIntent.play;
    }

    await _playlist.setQueue(
      tracks,
      startBaseIndex: startIndex,
      enableShuffle: shuffle,
    );

    _updateQueueWithNotFoundFlags();

    if (tracks.isNotEmpty) {
      final initialIndex = _playlist.currentOrderIndexNotifier.value ?? 0;
      // Use respectPauseIntent to allow concurrent playPause() calls to cancel playback
      await playFromQueueIndex(initialIndex, respectPauseIntent: true);

      // Re-check intent - user may have paused during load
      if (_userIntent == PlayIntent.pause) {
        await _transport.pause();
        isPlayingNotifier.value = false;
      }
    }
  }

  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false}) async {
    await _playlist.addTracks(tracks);
    _updateQueueWithNotFoundFlags();

    if (play && tracks.isNotEmpty) {
      final firstNewBaseIndex = _playlist.baseLength - tracks.length;
      final orderIndex =
          _playlist.orderIndexForBase(firstNewBaseIndex) ??
          _playlist.length - 1;
      await playFromQueueIndex(orderIndex, isAutoSkip: true);
    }
  }

  Future<void> shuffleQueue() async {
    final currentBaseIndex = _playlist.currentBaseIndex ?? 0;
    final wasPlaying = _userIntent == PlayIntent.play;

    await _playlist.reshuffle(keepBaseIndex: currentBaseIndex);
    _updateQueueWithNotFoundFlags();

    // Only start playback if we were already playing
    if (wasPlaying) {
      final idx = _playlist.currentOrderIndexNotifier.value ?? 0;
      await playFromQueueIndex(idx, isAutoSkip: true);
    }
  }

  Future<void> disableShuffle() async {
    final baseIndex = _playlist.currentBaseIndex ?? 0;
    final wasPlaying = _userIntent == PlayIntent.play;

    await _playlist.disableShuffle(keepBaseIndex: baseIndex);
    _updateQueueWithNotFoundFlags();

    // Only start playback if we were already playing
    if (wasPlaying) {
      final idx = _playlist.orderIndexForBase(baseIndex) ?? baseIndex;
      await playFromQueueIndex(idx, isAutoSkip: true);
    }
  }

  Future<void> _emitSongInfo({bool force = false}) async {
    final idx = _playlist.currentOrderIndexNotifier.value;
    final track = idx == null ? null : _playlist.trackForOrderIndex(idx);

    if (idx == null || track == null) {
      songInfoNotifier.value = null;
      return;
    }

    final position = await _transport.position;
    final duration = await _transport.duration;
    final isPlaying = isPlayingNotifier.value;

    // Check if track ended naturally
    if (!force &&
        duration > Duration.zero &&
        position >= duration &&
        _userIntent == PlayIntent.play) {
      await _skipToNext();
      return;
    }

    songInfoNotifier.value = SongInfo(
      title: track.title,
      artist: track.artist,
      album: '',
      isPlaying: isPlaying,
      position: position.inMilliseconds,
      duration: duration.inMilliseconds,
    );
  }

  Future<int> playlistSizeBytes() {
    return _playlist.persistentSizeBytes();
  }

  Future<List<AudioTrack>> scanFolder(String rootPath) async {
    final List<AudioTrack> tracks = [];
    final directory = Directory(rootPath);
    if (!await directory.exists()) return tracks;

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).replaceAll('.', '').toLowerCase();
      if (!_supportedExtensions.contains(ext)) continue;
      final title = p.basenameWithoutExtension(entity.path);
      tracks.add(AudioTrack(path: entity.path, title: title));
    }

    tracks.sort((a, b) => a.title.compareTo(b.title));
    return tracks;
  }

  static Set<String> _getSupportedExtensions(AudioTransport transport) {
    if (transport is JustAudioTransport) {
      return JustAudioTransport.supportedExtensions;
    } else if (transport is SoLoudTransport) {
      return SoLoudTransport.supportedExtensions;
    }
    // Default fallback
    return const {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus'};
  }
}
