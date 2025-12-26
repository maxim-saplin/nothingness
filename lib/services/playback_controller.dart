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
  final bool debugPlaybackLogs;

  // User intent - explicit state for what the user wants
  PlayIntent _userIntent = PlayIntent.pause;
  PlayIntent get userIntent => _userIntent;

  // State notifiers
  final ValueNotifier<SongInfo?> songInfoNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);

  // Track paths of files that failed to load (backend-agnostic)
  final Set<String> _failedTrackPaths = <String>{};

  // Track the path currently being loaded (pending load completion).

  // Used to correctly attribute error events even if we've moved to another track.
  String? _pendingLoadPath;
  // When the pending load started; used to attribute error timing correctly.
  DateTime? _pendingLoadStartedAt;
  // Last error event observed from transport, for timing-based attribution.
  String? _lastErrorEventPath;
  DateTime? _lastErrorEventAt;
  // Track transient error streak to avoid burning through the queue
  int _transientErrorCount = 0;
  DateTime? _transientWindowStart;
  // Timestamp when the current pending load was initiated. Helps ignore
  // spurious error events attributed to the current path before load completes.
  // These are no longer needed after simplifying error attribution.
  // Keeping declarations commented for future troubleshooting, but removing usage.
  // DateTime? _pendingLoadStartedAt;
  // bool _pendingLoadThrewError = false;

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
    this.debugPlaybackLogs = false,
  }) : _transport = transport,
       _playlist = playlist ?? PlaylistStore(),
       _supportedExtensions = _getSupportedExtensions(transport);

  void _log(String message) {
    if (debugPlaybackLogs) {
      debugPrint('[PlaybackController] $message');
    }
  }

  // Expose playlist notifiers
  ValueNotifier<int?> get currentIndexNotifier =>
      _playlist.currentOrderIndexNotifier;
  ValueNotifier<bool> get shuffleNotifier => _playlist.shuffleNotifier;

  Future<void> init() async {
    await _playlist.init();
    await _transport.init();

    // Listen to transport events
    _transportEventSub = _transport.eventStream.listen(_handleTransportEvent);
    _log('Initialized: subscribed to transport events');

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
        _log('Event ERROR path=${path ?? 'null'}');
        _lastErrorEventPath = path;
        _lastErrorEventAt = DateTime.now();
        _handleTrackError(path);
      case TransportEndedEvent(:final path):
        _log('Event ENDED path=${path ?? 'null'}');
        _handleTrackEnded(path);
      case TransportLoadedEvent(:final path):
        _log('Event LOADED path=${path ?? 'null'}');
        _onTrackLoaded(path);
      case TransportPositionEvent():
        // Position updates handled by timer
        break;
    }
  }

  void _handleTrackError(String? path) {
    if (path == null) return;

    // Only treat errors as load failures when they match the track currently
    // being loaded. Errors for any other path (including the current/playing
    // track after we've moved on) are ignored to prevent misattribution.
    final isForPendingLoad = path == _pendingLoadPath;
    if (!isForPendingLoad) {
      _log(
        'Ignore error: not pending. path=$path pending=${_pendingLoadPath ?? 'null'}',
      );
      return;
    }

    // Do not mark as failed here for pending loads. Genuine failures will be
    // handled by the thrown error in load()'s catch path. This avoids
    // misattributed current-path errors flagging valid tracks.
    if (_pendingLoadPath == path) {
      _log(
        'Pending error for same path; clearing pending without marking failed. path=$path',
      );
      _pendingLoadPath = null;
    }
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
    // Clear pending load path since load succeeded
    if (_pendingLoadPath == path) {
      _log('OnLoaded: clearing pending for path=$path');
      _pendingLoadPath = null;
      _pendingLoadStartedAt = null;
    }
    // Clear the failed flag if track now loads successfully
    if (_failedTrackPaths.remove(path)) {
      _log('OnLoaded: removed failed flag for path=$path');
      _updateQueueWithNotFoundFlags();
    }
    _emitSongInfo(force: true);
  }

  Future<void> _skipToNext() async {
    final nextIdx = _playlist.nextOrderIndex();
    _log('SkipToNext: nextIdx=${nextIdx?.toString() ?? 'null'}');
    if (nextIdx != null) {
      await playFromQueueIndex(nextIdx, isAutoSkip: true);
    } else {
      // End of queue
      isPlayingNotifier.value = false;
      await _transport.pause();
      _log('SkipToNext: end of queue, paused');
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
    _log(
      'playFromQueueIndex: orderIndex=$orderIndex autoSkip=$isAutoSkip respectPause=$respectPauseIntent',
    );
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
      _log('UserTap: suppress auto-skip');
    }

    // Track this as pending load - error handler will check this
    _pendingLoadPath = track.path;
    _pendingLoadStartedAt = DateTime.now();
    _log('StartLoad: path=${track.path}');

    try {
      await _transport.load(
        track.path,
        title: track.title,
        artist: track.artist,
      );

      // Clear pending load path on success
      _pendingLoadPath = null;
      _pendingLoadStartedAt = null;
      _log('LoadSuccess: path=${track.path}');

      // Re-enable auto-skip
      if (isUserTap) {
        _suppressAutoSkip = false;
        _log('UserTap: re-enable auto-skip');
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
      _log('Play: path=${track.path}');

      // Check again if user paused while starting playback
      if (_userIntent == PlayIntent.pause) {
        await _transport.pause();
        isPlayingNotifier.value = false;
      }
    } catch (e) {
      _log('LoadError: path=${track.path} error=$e');

      // Special-case transient transport failures (e.g., JustAudio "Connection aborted")
      final isTransient = _isTransientTransportError(e);
      if (isTransient) {
        _log('TransientError: path=${track.path}');
        final now = DateTime.now();
        if (_transientWindowStart == null ||
            now.difference(_transientWindowStart!).inSeconds > 5) {
          _transientWindowStart = now;
          _transientErrorCount = 0;
        }

        // Attempt a short backoff retry once for transient errors
        try {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          _pendingLoadPath = track.path;
          _pendingLoadStartedAt = DateTime.now();
          await _transport.load(
            track.path,
            title: track.title,
            artist: track.artist,
          );
          _pendingLoadPath = null;
          _pendingLoadStartedAt = null;
          _log('TransientRetrySuccess: path=${track.path}');

          if (isUserTap) {
            _suppressAutoSkip = false;
          }

          _userIntent = PlayIntent.play;
          await _transport.play();
          _emitSongInfo(force: true);
          return;
        } catch (_) {
          _log('TransientRetryFailed: path=${track.path}');
          _transientErrorCount += 1;
          // Do not mark as failed for transient errors
          _pendingLoadPath = null;
          _pendingLoadStartedAt = null;
          _updateQueueWithNotFoundFlags();

          // Circuit breaker: too many transients in a short window => pause
          if (_transientErrorCount >= 3) {
            _log('TransientPause: count=$_transientErrorCount');
            isPlayingNotifier.value = false;
            await _transport.pause();
            _emitSongInfo(force: true);
            return;
          }

          if (_userIntent == PlayIntent.play && !_suppressAutoSkip) {
            _log('TransientSkip: intent=play');
            await _skipToNext();
          } else {
            _log('TransientNoSkip: intent=pause or suppressed');
            isPlayingNotifier.value = false;
          }
          _emitSongInfo(force: true);
          return;
        }
      }

      final pendingStartedAt = _pendingLoadStartedAt;
      final lastErrAt = _lastErrorEventAt;
      final lastErrPath = _lastErrorEventPath;
      final isErrorLikelyFromThisLoad =
          lastErrPath == track.path &&
          pendingStartedAt != null &&
          lastErrAt != null &&
          lastErrAt.isAfter(pendingStartedAt);
      _log(
        'ErrorAttribution: lastErrPath=${lastErrPath ?? 'null'} lastErrAt=${lastErrAt?.toIso8601String() ?? 'null'} pendingStart=${pendingStartedAt?.toIso8601String() ?? 'null'} likely=$isErrorLikelyFromThisLoad',
      );

      // If the error seems ambiguous (no matching recent error event for this
      // load), retry once before marking as failed.
      if (!isErrorLikelyFromThisLoad) {
        _log('RetryOnce: path=${track.path}');
        try {
          // Re-establish pending state and attempt a single retry.
          _pendingLoadPath = track.path;
          _pendingLoadStartedAt = DateTime.now();
          await _transport.load(
            track.path,
            title: track.title,
            artist: track.artist,
          );
          _pendingLoadPath = null;
          _pendingLoadStartedAt = null;
          _log('RetrySuccess: path=${track.path}');

          if (isUserTap) {
            _suppressAutoSkip = false;
          }

          // Success on retry: proceed to play
          _userIntent = PlayIntent.play;
          await _transport.play();
          _emitSongInfo(force: true);
          return;
        } catch (_) {
          _log('RetryFailed: path=${track.path}');
          // Fall through to failure handling
        }
      }

      // Treat thrown load errors as a failure of this track even if
      // the transport does not emit a well-formed error event.
      _failedTrackPaths.add(track.path);
      _pendingLoadPath = null;
      _pendingLoadStartedAt = null;
      _updateQueueWithNotFoundFlags();
      debugPrint('Error playing track: $e');
      // If user intends to play and this was not a suppressed user tap,
      // advance to the next track immediately. This covers transports that
      // throw on load without a timely error event.
      if (_userIntent == PlayIntent.play && !_suppressAutoSkip) {
        _log('SkipAfterError: intent=play');
        await _skipToNext();
      } else {
        // Revert visual state on error
        _log('PauseAfterError: intent=pause or suppressed');
        isPlayingNotifier.value = false;
      }
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

    // Note: end-of-track advancement is handled via TransportEndedEvent.
    // Avoid duplicate skipping here to prevent race conditions during source transitions.

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

  bool _isTransientTransportError(Object error) {
    final s = error.toString().toLowerCase();
    // Heuristics: JustAudio PlayerException "Connection aborted" often
    // occurs during rapid track changes or codec re-init and is transient.
    return s.contains('connection aborted') || s.contains('10000000');
  }
}
