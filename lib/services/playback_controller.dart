import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/audio_track.dart';
import '../models/song_info.dart';
import 'audio_transport.dart';
import 'metadata_extractor.dart';
import 'playlist_store.dart';
import 'soloud_transport.dart';

/// Represents the user's explicit intent for playback state.
enum PlayIntent {
  /// User wants music to play
  play,

  /// User wants silence (paused)
  pause,
}

/// Internal classification of why a selection/play attempt is happening.
enum _SelectionReason { userTap, previous, autoAdvance, setQueue, other }

/// Single source of truth for playback logic.
/// Manages user intent, queue, error recovery, and coordinates with AudioTransport.
class PlaybackController {
  final AudioTransport _transport;
  final PlaylistStore _playlist;
  final bool debugPlaybackLogs;
  final bool preflightFileExists;
  final Future<bool> Function(String path) _fileExists;
  final bool captureRecentLogs;
  final int recentLogCapacity;
  final List<String> _recentLogs = <String>[];

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
  // (Intentionally no error timing attribution fields: we avoid misattribution
  // by only acting on errors that match the pending load path.)
  // Track transient error streak to avoid burning through the queue
  int _transientErrorCount = 0;
  DateTime? _transientWindowStart;
  // Timestamp when the current pending load was initiated. Helps ignore
  // spurious error events attributed to the current path before load completes.
  // These are no longer needed after simplifying error attribution.
  // Keeping declarations commented for future troubleshooting, but removing usage.
  // DateTime? _pendingLoadStartedAt;
  // bool _pendingLoadThrewError = false;

  // Operation generation to ignore stale async continuations (rapid taps).
  int _opGeneration = 0;

  _SelectionReason _lastSelectionReason = _SelectionReason.other;
  int _lastSelectionDirection = 1;

  // Diagnostics: last error attribution
  String? _lastErrorPath;
  String? _lastErrorReason;
  String? _lastErrorMessage;
  DateTime? _lastErrorAt;

  StreamSubscription<TransportEvent>? _transportEventSub;
  Timer? _positionTimer;

  // Wrapper notifier that includes isNotFound flags
  final ValueNotifier<List<AudioTrack>> queueNotifier = ValueNotifier(const []);

  final Set<String> _supportedExtensions;

  PlaybackController({
    required AudioTransport transport,
    PlaylistStore? playlist,
    this.debugPlaybackLogs = false,
    this.preflightFileExists = true,
    Future<bool> Function(String path)? fileExists,
    this.captureRecentLogs = false,
    this.recentLogCapacity = 50,
  }) : _transport = transport,
       _playlist = playlist ?? PlaylistStore(),
       _fileExists = fileExists ?? _defaultFileExists,
       _supportedExtensions = _getSupportedExtensions(transport);

  void _log(String message) {
    if (captureRecentLogs || debugPlaybackLogs) {
      _recentLogs.add(message);
      final cap = max(1, recentLogCapacity);
      if (_recentLogs.length > cap) {
        _recentLogs.removeRange(0, _recentLogs.length - cap);
      }
    }
    if (debugPlaybackLogs) {
      debugPrint('[PlaybackController] $message');
    }
  }

  static Future<bool> _defaultFileExists(String path) => File(path).exists();

  /// Returns a snapshot of recent controller logs (if enabled).
  ///
  /// This is primarily intended for test/diagnostic tooling.
  List<String> recentLogs() => List<String>.unmodifiable(_recentLogs);

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
          debugPrint('Failed to load initial track: $e');
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

    // We only act on errors we can confidently attribute to the track currently
    // being loaded. Real transports can emit late/spurious errors for the
    // "current" path; those must not corrupt playback.
    final isForPendingLoad = path == _pendingLoadPath;
    if (!isForPendingLoad) {
      _log(
        'Ignore error: not pending. path=$path pending=${_pendingLoadPath ?? 'null'}',
      );
      return;
    }

    // Mark failed immediately so UI turns red, but do not attempt to advance
    // from the event handler. The in-flight load() path will deterministically
    // handle the failure (throwing transports) and advance from a single place.
    //
    // This avoids double-advancing and prevents background async work from
    // outliving tests/dispose.
    _log(
      'PendingLoadErrorEvent: path=$path (mark failed; defer advance to load/catch)',
    );
    _lastErrorPath = path;
    _lastErrorReason = 'transport_error_event';
    _lastErrorMessage = 'TransportErrorEvent';
    _lastErrorAt = DateTime.now();
    if (_failedTrackPaths.add(path)) {
      _updateQueueWithNotFoundFlags();
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
      await playFromQueueIndex(nextIdx, isAutoSkip: true, direction: 1);
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
      await playFromQueueIndex(nextIdx, isAutoSkip: true, direction: 1);
    }
  }

  Future<void> previous() async {
    _userIntent = PlayIntent.play; // Navigation implies play intent

    // Check if there's a current track loaded
    final currentIdx = _playlist.currentOrderIndexNotifier.value;
    if (currentIdx == null) {
      // No track loaded, try to go to previous song
      final prevIdx = _playlist.previousOrderIndex();
      if (prevIdx != null) {
        await playFromQueueIndex(prevIdx, isAutoSkip: true, direction: -1);
      }
      return;
    }

    // Get current playback position
    try {
      final position = await _transport.position;
      const threshold = Duration(seconds: 3);

      if (position > threshold) {
        // Position > 3 seconds: restart current song
        await seek(Duration.zero);
        // Ensure playback starts if paused
        if (_userIntent == PlayIntent.play && !isPlayingNotifier.value) {
          await _transport.play();
          isPlayingNotifier.value = true;
          _emitSongInfo();
        }
      } else {
        // Position <= 3 seconds: go to previous song
        final prevIdx = _playlist.previousOrderIndex();
        if (prevIdx != null) {
          await playFromQueueIndex(prevIdx, isAutoSkip: true, direction: -1);
        }
      }
    } catch (e) {
      // Position unavailable: fall back to previous song behavior
      _log('Error getting position in previous(): $e');
      final prevIdx = _playlist.previousOrderIndex();
      if (prevIdx != null) {
        await playFromQueueIndex(prevIdx, isAutoSkip: true, direction: -1);
      }
    }
  }

  Future<void> playFromQueueIndex(
    int orderIndex, {
    bool isAutoSkip = false,
    bool respectPauseIntent = false,
    int direction = 1,
  }) async {
    final op = ++_opGeneration;
    _log(
      'playFromQueueIndex: orderIndex=$orderIndex autoSkip=$isAutoSkip respectPause=$respectPauseIntent dir=$direction',
    );
    if (orderIndex < 0 || orderIndex >= _playlist.length) return;

    final track = _playlist.trackForOrderIndex(orderIndex);
    if (track == null) return;

    final isUserTap = !isAutoSkip && !respectPauseIntent;
    _lastSelectionReason = isUserTap
        ? _SelectionReason.userTap
        : (respectPauseIntent
              ? _SelectionReason.setQueue
              : (isAutoSkip
                    ? (direction < 0
                          ? _SelectionReason.previous
                          : _SelectionReason.autoAdvance)
                    : _SelectionReason.other));
    _lastSelectionDirection = direction == 0 ? 1 : direction.sign;

    // If caller wants to respect pause intent (e.g., setQueue), check before proceeding
    if (respectPauseIntent && _userIntent == PlayIntent.pause) {
      await _playlist.setCurrentOrderIndex(orderIndex);
      isPlayingNotifier.value = false;
      _emitSongInfo(force: true);
      return;
    }

    // Navigation/tap implies play (even if previously paused); setQueue may
    // opt out via respectPauseIntent.
    if (!respectPauseIntent) {
      _userIntent = PlayIntent.play;
    }

    await _playWithAutoAdvance(
      orderIndex,
      op: op,
      direction: _lastSelectionDirection,
      reason: _lastSelectionReason,
      respectPauseIntent: respectPauseIntent,
    );
  }

  bool _shouldPreflightExists(String path) {
    if (!preflightFileExists) return false;
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) {
      // content://, http(s)://, etc. can't be preflighted via dart:io File.
      return false;
    }
    // Avoid preflighting empty/odd paths.
    if (path.isEmpty) return false;
    return true;
  }

  Future<void> _playWithAutoAdvance(
    int startOrderIndex, {
    required int op,
    required int direction,
    required _SelectionReason reason,
    required bool respectPauseIntent,
  }) async {
    if (_playlist.length == 0) return;
    final dir = direction == 0 ? 1 : direction.sign;
    var idx = startOrderIndex;

    for (var attempts = 0; attempts < _playlist.length; attempts++) {
      if (op != _opGeneration) return;
      if (idx < 0 || idx >= _playlist.length) break;

      final track = _playlist.trackForOrderIndex(idx);
      if (track == null) break;

      final isKnownFailed = _failedTrackPaths.contains(track.path);
      // If already known failed, normally keep scanning.
      // Exception: for a direct user tap on the requested track, allow a retry
      // attempt (the file may have been restored).
      if (isKnownFailed &&
          !(reason == _SelectionReason.userTap && idx == startOrderIndex)) {
        _updateQueueWithNotFoundFlags();
        idx += dir;
        continue;
      }

      // Optional deterministic preflight for filesystem paths.
      if (_shouldPreflightExists(track.path)) {
        final exists = await _fileExists(track.path);
        if (!exists) {
          _log('PreflightMissing: path=${track.path}');
          _lastErrorPath = track.path;
          _lastErrorReason = 'preflight_missing';
          _lastErrorMessage = 'File does not exist';
          _lastErrorAt = DateTime.now();
          _failedTrackPaths.add(track.path);
          _updateQueueWithNotFoundFlags();
          idx += dir;
          continue;
        }
      }

      await _playlist.setCurrentOrderIndex(idx);

      // Respect pause intent for setQueue only.
      if (respectPauseIntent && _userIntent == PlayIntent.pause) {
        isPlayingNotifier.value = false;
        _emitSongInfo(force: true);
        return;
      }

      // Optimistic UI update for responsiveness.
      isPlayingNotifier.value = true;

      _pendingLoadPath = track.path;
      _log('StartLoad: path=${track.path}');

      try {
        await _transport.load(
          track.path,
          title: track.title,
          artist: track.artist,
        );
        if (op != _opGeneration) return;

        _pendingLoadPath = null;
        _log('LoadSuccess: path=${track.path}');

        if (_failedTrackPaths.remove(track.path)) {
          _updateQueueWithNotFoundFlags();
        }

        // Commit to play intent and start playback.
        _userIntent = PlayIntent.play;
        await _transport.play();
        if (op != _opGeneration) return;

        if (_userIntent == PlayIntent.pause) {
          await _transport.pause();
          isPlayingNotifier.value = false;
        }

        _emitSongInfo(force: true);
        return;
      } catch (e) {
        if (op != _opGeneration) return;
        _log('LoadError: path=${track.path} error=$e');
        _lastErrorPath = track.path;
        _lastErrorReason = _isTransientTransportError(e)
            ? 'transport_load_transient'
            : 'transport_load_error';
        _lastErrorMessage = e.toString();
        _lastErrorAt = DateTime.now();

        // Transient failures: retry briefly, then continue scanning.
        if (_isTransientTransportError(e)) {
          final now = DateTime.now();
          if (_transientWindowStart == null ||
              now.difference(_transientWindowStart!).inSeconds > 5) {
            _transientWindowStart = now;
            _transientErrorCount = 0;
          }
          try {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (op != _opGeneration) return;
            _pendingLoadPath = track.path;
            await _transport.load(
              track.path,
              title: track.title,
              artist: track.artist,
            );
            if (op != _opGeneration) return;
            _pendingLoadPath = null;

            _userIntent = PlayIntent.play;
            await _transport.play();
            _emitSongInfo(force: true);
            return;
          } catch (_) {
            _transientErrorCount += 1;
            _pendingLoadPath = null;

            if (_transientErrorCount >= 3) {
              isPlayingNotifier.value = false;
              await _transport.pause();
              _emitSongInfo(force: true);
              return;
            }

            idx += dir;
            continue;
          }
        }

        // Definitive failure: mark failed and advance deterministically.
        _failedTrackPaths.add(track.path);
        _pendingLoadPath = null;
        _updateQueueWithNotFoundFlags();
        debugPrint('Error playing track: $e');

        idx += dir;
        continue;
      }
    }

    // No playable tracks found in the scan range.
    isPlayingNotifier.value = false;
    await _transport.pause();
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
      await playFromQueueIndex(
        initialIndex,
        respectPauseIntent: true,
        direction: 1,
      );

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
      if (force || songInfoNotifier.value != null) {
        songInfoNotifier.value = null;
      }
      return;
    }

    final position = await _transport.position;
    final duration = await _transport.duration;
    final isPlaying = isPlayingNotifier.value;

    // Note: end-of-track advancement is handled via TransportEndedEvent.
    // Avoid duplicate skipping here to prevent race conditions during source transitions.

    final nextSongInfo = SongInfo(
      track: track,
      isPlaying: isPlaying,
      position: position.inMilliseconds,
      duration: duration.inMilliseconds,
    );

    if (!force) {
      final current = songInfoNotifier.value;
      if (current != null &&
          current.track.path == nextSongInfo.track.path &&
          current.isPlaying == nextSongInfo.isPlaying &&
          current.position == nextSongInfo.position &&
          current.duration == nextSongInfo.duration) {
        return;
      }
    }

    songInfoNotifier.value = nextSongInfo;
  }

  Future<int> playlistSizeBytes() {
    return _playlist.persistentSizeBytes();
  }

  Future<List<AudioTrack>> scanFolder(String rootPath) async {
    final List<AudioTrack> tracks = [];
    final directory = Directory(rootPath);
    if (!await directory.exists()) return tracks;

    final extractor = createMetadataExtractor();

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).replaceAll('.', '').toLowerCase();
      if (!_supportedExtensions.contains(ext)) continue;
      try {
        final track = await extractor.extractMetadata(entity.path);
        tracks.add(track);
      } catch (e) {
        // Fallback to filename if extraction fails
        final title = p.basenameWithoutExtension(entity.path);
        tracks.add(AudioTrack(path: entity.path, title: title));
      }
    }

    tracks.sort((a, b) => a.title.compareTo(b.title));
    return tracks;
  }

  static Set<String> _getSupportedExtensions(AudioTransport transport) {
    if (transport is SoLoudTransport) {
      return SoLoudTransport.supportedExtensions;
    }
    return const {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus'};
  }

  bool _isTransientTransportError(Object error) {
    final s = error.toString().toLowerCase();
    // Heuristics: JustAudio PlayerException "Connection aborted" often
    // occurs during rapid track changes or codec re-init and is transient.
    return s.contains('connection aborted') || s.contains('10000000');
  }

  /// Structured snapshot of playback controller state for diagnostics.
  ///
  /// This is intended for debugging and emulator automation.
  Map<String, Object?> diagnosticsSnapshot() {
    final idx = _playlist.currentOrderIndexNotifier.value;
    final track = idx == null ? null : _playlist.trackForOrderIndex(idx);
    return <String, Object?>{
      'userIntent': _userIntent.name,
      'isPlaying': isPlayingNotifier.value,
      'currentOrderIndex': idx,
      'currentPath': track?.path,
      'queueLength': _playlist.length,
      'failedTrackPaths': _failedTrackPaths.toList()..sort(),
      'pendingLoadPath': _pendingLoadPath,
      'lastSelectionReason': _lastSelectionReason.name,
      'lastSelectionDirection': _lastSelectionDirection,
      'lastError': <String, Object?>{
        'path': _lastErrorPath,
        'reason': _lastErrorReason,
        'message': _lastErrorMessage,
        'at': _lastErrorAt?.toIso8601String(),
      },
      'recentLogs': recentLogs(),
    };
  }
}
