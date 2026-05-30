import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/audio_track.dart';
import '../models/song_info.dart';
import 'audio_transport.dart';
import 'metadata_extractor.dart';
import 'playlist_store.dart';
import 'soloud_transport.dart';

/// The user's explicit intent for playback state.
enum PlayIntent { play, pause }

/// Queue + index snapshot for a search session (B-014); restored on
/// `exitSearchSession` without reloading the playing track.
class _SearchSession {
  _SearchSession({required this.savedQueue, required this.savedIndex});

  final List<AudioTrack> savedQueue;
  final int savedIndex;
}

/// Why a selection/play attempt is happening.
enum _SelectionReason { userTap, previous, autoAdvance, setQueue, other }

/// Single source of truth for playback: user intent, queue, error recovery,
/// and coordination with the AudioTransport.
class PlaybackController {
  final AudioTransport _transport;
  final PlaylistStore _playlist;
  final bool debugPlaybackLogs;
  final bool preflightFileExists;
  final Future<bool> Function(String path) _fileExists;
  final bool captureRecentLogs;
  final int recentLogCapacity;
  final List<String> _recentLogs = <String>[];

  PlayIntent _userIntent = PlayIntent.pause;
  PlayIntent get userIntent => _userIntent;
  final ValueNotifier<SongInfo?> songInfoNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);

  // One-shot: a track played outside the queue. On natural end the queue is
  // restored at `_queueIndexAtOneShotStart + 1`; explicit prev/next clears it.
  bool _oneShot = false;
  int? _queueIndexAtOneShotStart;
  AudioTrack? _oneShotTrack;
  bool _oneShotRepeatOne = false;
  final ValueNotifier<bool> isOneShotNotifier = ValueNotifier(false);
  bool get isOneShot => _oneShot;
  AudioTrack? get oneShotTrack => _oneShotTrack;

  // Search-session state (B-014): original queue/index preserved for restore.
  _SearchSession? _activeSearchSession;
  bool get isInSearchSession => _activeSearchSession != null;

  // Paths of files that failed to load (backend-agnostic).
  final Set<String> _failedTrackPaths = <String>{};

  // Path being loaded; only errors matching it are acted on (transports emit
  // late/spurious errors for a path after we've moved on).
  String? _pendingLoadPath;
  // Transient error streak guard, to avoid burning through the queue.
  int _transientErrorCount = 0;
  DateTime? _transientWindowStart;

  // Operation generation to ignore stale async continuations (rapid taps).
  int _opGeneration = 0;
  // B-036: true while an end-triggered advance is in flight; guards against
  // duplicate/stale `ended` events double-advancing and skipping a track.
  bool _handlingEnded = false;
  _SelectionReason _lastSelectionReason = _SelectionReason.other;
  int _lastSelectionDirection = 1;

  // Diagnostics: last-error attribution.
  String? _lastErrorPath;
  String? _lastErrorReason;
  String? _lastErrorMessage;
  DateTime? _lastErrorAt;
  DateTime? _endedAtQueueTailAt;

  StreamSubscription<TransportEvent>? _transportEventSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesSub;
  bool _pausedByInterruption = false;
  Timer? _positionTimer;

  // Audio-event ring buffer for diagnosing route changes / interruptions.
  final List<String> _audioEvents = <String>[];
  static const int _audioEventsCap = 300;
  // Queue mirror including isNotFound flags.
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

  static void _appendCapped(List<String> buffer, String entry, int cap) {
    buffer.add(entry);
    if (buffer.length > cap) {
      buffer.removeRange(0, buffer.length - cap);
    }
  }

  void _log(String message) {
    if (captureRecentLogs || debugPlaybackLogs) {
      _appendCapped(_recentLogs, message, max(1, recentLogCapacity));
    }
    if (debugPlaybackLogs) {
      debugPrint('[PlaybackController] $message');
    }
  }

  static Future<bool> _defaultFileExists(String path) => File(path).exists();

  Future<void> _loadTrack(AudioTrack track) =>
      _transport.load(track.path, title: track.title, artist: track.artist);

  // The track at the current order index, or null if none is selected.
  AudioTrack? get _currentTrack {
    final idx = _playlist.currentOrderIndexNotifier.value;
    return idx == null ? null : _playlist.trackForOrderIndex(idx);
  }

  void _recordError(String path, String reason, String message) {
    _lastErrorPath = path;
    _lastErrorReason = reason;
    _lastErrorMessage = message;
    _lastErrorAt = DateTime.now();
  }

  /// Recent controller logs (if enabled), for test/diagnostics.
  List<String> recentLogs() => List<String>.unmodifiable(_recentLogs);

  ValueNotifier<int?> get currentIndexNotifier =>
      _playlist.currentOrderIndexNotifier;
  ValueNotifier<bool> get shuffleNotifier => _playlist.shuffleNotifier;

  Future<void> init() async {
    await _playlist.init();
    await _transport.init();

    _transportEventSub = _transport.eventStream.listen(_handleTransportEvent);
    _log('Initialized: subscribed to transport events');

    // Audio focus / interruption events; unavailable in some test/host envs.
    try {
      final session = await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen(
        _onInterruption,
      );
      _noisySub = session.becomingNoisyEventStream.listen(
        (_) => _onBecomingNoisy(),
      );
      _devicesSub = session.devicesChangedEventStream.listen(_onDevicesChanged);
      _log('Initialized: subscribed to audio session events');
    } catch (e) {
      _log('AudioSession unavailable: $e');
    }

    _playlist.queueNotifier.addListener(_updateQueueWithNotFoundFlags);
    _playlist.currentOrderIndexNotifier.addListener(_onIndexChanged);
    _playlist.shuffleNotifier.addListener(_onShuffleChanged);

    _positionTimer = _newPositionTimer();
    _updateQueueWithNotFoundFlags();

    // Preload the current track so it's ready to play.
    final track = _currentTrack;
    if (track != null) {
      try {
        await _loadTrack(track);
      } catch (e) {
        // Ignore startup load errors; handled when the user tries to play.
        debugPrint('Failed to load initial track: $e');
      }
    }

    await _emitSongInfo(force: true);
  }

  Timer _newPositionTimer() =>
      Timer.periodic(const Duration(milliseconds: 300), (_) => _emitSongInfo());

  /// Suspend periodic timers to save battery while the app is backgrounded.
  void suspendTimers() {
    _positionTimer?.cancel();
    _positionTimer = null;
    _transport.suspendTimers();
  }

  /// Resume periodic timers when returning to foreground.
  void resumeTimers() {
    _positionTimer ??= _newPositionTimer();
    _transport.resumeTimers();
  }

  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _transportEventSub?.cancel();
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    await _devicesSub?.cancel();
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

  void _logAudioEvent(String tag, [Map<String, Object?>? data]) {
    final ts = DateTime.now().toIso8601String();
    final dataStr = (data == null || data.isEmpty)
        ? ''
        : ' ${data.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    _appendCapped(_audioEvents, '$ts $tag$dataStr', _audioEventsCap);
  }

  void _onInterruption(AudioInterruptionEvent event) {
    _logAudioEvent('interruption', {
      'begin': event.begin,
      'type': event.type.name,
    });

    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          return; // Keep playing; OS attenuates volume.
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (isPlayingNotifier.value) {
            // Don't flip _userIntent — the user still wants to play.
            _pausedByInterruption = true;
            unawaited(_transport.pause());
            isPlayingNotifier.value = false;
          }
      }
      return;
    }

    // Interruption ended (event.begin == false).
    if (event.type == AudioInterruptionType.duck) return;
    // unknown == permanent focus loss: do not auto-resume.
    final shouldResume = event.type == AudioInterruptionType.pause &&
        _pausedByInterruption &&
        _userIntent == PlayIntent.play;
    _pausedByInterruption = false;
    if (shouldResume) {
      unawaited(_transport.play());
      isPlayingNotifier.value = true;
    }
  }

  void _onBecomingNoisy() {
    _logAudioEvent('becomingNoisy');
    // Headphones unplugged / BT disconnected: treat as explicit pause per
    // Android guidance — never auto-resume.
    _pausedByInterruption = false;
    _userIntent = PlayIntent.pause;
    if (isPlayingNotifier.value) {
      unawaited(_transport.pause());
      isPlayingNotifier.value = false;
    }
  }

  void _onDevicesChanged(AudioDevicesChangedEvent event) {
    String outputs(Iterable<AudioDevice> devices) => devices
        .where((d) => d.isOutput)
        .map((d) => '${d.type.name}:${d.name}')
        .join(',');
    final added = outputs(event.devicesAdded);
    final removed = outputs(event.devicesRemoved);
    if (added.isEmpty && removed.isEmpty) return;
    _logAudioEvent('devicesChanged', {'added': added, 'removed': removed});
  }

  /// Debug seam for tests / `ext.nothingness.simulateInterruption`.
  void debugSimulateInterruption(AudioInterruptionEvent event) =>
      _onInterruption(event);

  /// Debug seam for tests / `ext.nothingness.simulateNoisy`.
  void debugSimulateBecomingNoisy() => _onBecomingNoisy();

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
        break; // Handled by the timer.
    }
  }

  void _handleTrackError(String? path) {
    if (path == null) return;
    _logAudioEvent('transportError', {'path': path});

    if (path != _pendingLoadPath) {
      _log('Ignore error: not pending. path=$path');
      return;
    }

    // Mark failed now (UI turns red); defer the advance to the in-flight
    // load() catch so advancing happens from one place.
    _log('PendingLoadError: path=$path (defer advance to load/catch)');
    _recordError(path, 'transport_error_event', 'TransportErrorEvent');
    if (_failedTrackPaths.add(path)) {
      _updateQueueWithNotFoundFlags();
    }
  }

  void _handleTrackEnded(String? path) {
    _logAudioEvent('transportEnded', {'path': path ?? ''});

    // B-036: ignore ended while an advance is in flight — a duplicate event
    // before the first advance commits would double-advance and skip a track.
    if (_handlingEnded) {
      _log('Ignore ended: advance already in flight path=${path ?? 'null'}');
      return;
    }

    // One-shot: loop in place (repeat-one) or restore the queue.
    if (_oneShot) {
      _handlingEnded = true;
      final future = _oneShotRepeatOne
          ? _restartOneShot()
          : _finishOneShot(manual: false);
      unawaited(future.whenComplete(() => _handlingEnded = false));
      return;
    }

    if (_userIntent == PlayIntent.play) {
      _handlingEnded = true;
      unawaited(_skipToNext().whenComplete(() => _handlingEnded = false));
    } else {
      isPlayingNotifier.value = false;
    }
  }

  void _onTrackLoaded(String? path) {
    if (path == null) return;
    _logAudioEvent('transportLoaded', {'path': path});
    if (_pendingLoadPath == path) {
      _log('OnLoaded: clearing pending for path=$path');
      _pendingLoadPath = null;
    }
    if (_failedTrackPaths.remove(path)) {
      _log('OnLoaded: removed failed flag for path=$path');
      _updateQueueWithNotFoundFlags();
    }
    _emitSongInfo(force: true);
  }

  // Pause the transport and re-emit; [resetIntent] also flips intent to pause.
  Future<void> _stopPlayback({bool resetIntent = false}) async {
    isPlayingNotifier.value = false;
    if (resetIntent) _userIntent = PlayIntent.pause;
    await _transport.pause();
    _emitSongInfo(force: true);
  }

  // Honor a pause intent that flipped while a load/play was in flight.
  Future<void> _pauseIfIntentPause() async {
    if (_userIntent != PlayIntent.pause) return;
    await _transport.pause();
    isPlayingNotifier.value = false;
  }

  Future<void> _skipToNext() async {
    final nextIdx = _playlist.nextOrderIndex();
    _log('SkipToNext: nextIdx=${nextIdx?.toString() ?? 'null'}');
    if (nextIdx != null) {
      await playFromQueueIndex(nextIdx, isAutoSkip: true, direction: 1);
    } else {
      _endedAtQueueTailAt = DateTime.now();
      _log('SkipToNext: end of queue, paused');
      await _stopPlayback();
    }
  }

  /// Best-effort gapless look-ahead (B-037): preload the next auto-advance
  /// track. No-op at the tail, during a one-shot, or for a known-failed track.
  void _preloadNext() {
    if (_oneShot) return;
    final nextIdx = _playlist.nextOrderIndex();
    if (nextIdx == null) return;
    final track = _playlist.trackForOrderIndex(nextIdx);
    if (track == null) return;
    if (_failedTrackPaths.contains(track.path)) return;
    unawaited(_transport.preload(track.path));
  }

  void _updateQueueWithNotFoundFlags() {
    queueNotifier.value = [
      for (final t in _playlist.queueNotifier.value)
        _failedTrackPaths.contains(t.path) ? t.copyWith(isNotFound: true) : t,
    ];
  }

  Future<void> playPause() async {
    if (_playlist.length == 0) return;

    // Nothing loaded yet: start from the current/first index.
    final currentIdx = _playlist.currentOrderIndexNotifier.value;
    if (currentIdx == null) {
      final idx = _playlist.length > 0 ? 0 : null;
      if (idx != null) {
        await playFromQueueIndex(idx, isAutoSkip: true);
      }
      return;
    }

    // Toggle on user intent (source of truth); optimistic UI update.
    if (_userIntent == PlayIntent.play) {
      _userIntent = PlayIntent.pause;
      isPlayingNotifier.value = false;
      await _transport.pause();
    } else {
      _userIntent = PlayIntent.play;
      isPlayingNotifier.value = true;
      await _transport.play();
      // Correct if intent flipped to pause while starting.
      await _pauseIfIntentPause();
    }
    _emitSongInfo();
  }

  // Auto-skip play to [orderIndex] in [direction], if non-null.
  Future<void> _stepToIndex(int? orderIndex, int direction) async {
    if (orderIndex != null) {
      await playFromQueueIndex(orderIndex, isAutoSkip: true, direction: direction);
    }
  }

  Future<void> next() async {
    _userIntent = PlayIntent.play; // Navigation implies play.
    if (_oneShot) {
      await _finishOneShot(manual: true);
      return;
    }
    await _stepToIndex(_playlist.nextOrderIndex(), 1);
  }

  Future<void> _stepToPreviousIndex() =>
      _stepToIndex(_playlist.previousOrderIndex(), -1);

  Future<void> _startTransportPlay() async {
    await _transport.play();
    isPlayingNotifier.value = true;
    _emitSongInfo();
  }

  Future<void> previous() async {
    _userIntent = PlayIntent.play; // Navigation implies play.
    if (_oneShot) {
      await _finishOneShot(manual: true, backward: true);
      return;
    }

    final currentIdx = _playlist.currentOrderIndexNotifier.value;
    if (currentIdx == null) {
      await _stepToPreviousIndex();
      return;
    }

    final isTail = currentIdx == _playlist.length - 1;
    try {
      final position = await _transport.position;
      // At the tail in an ended-like state, restart the last track rather than
      // jumping to last-1 after natural completion.
      final isEndedLikeState =
          !isPlayingNotifier.value || position == Duration.zero;
      final endedTailRecently =
          isTail &&
          _endedAtQueueTailAt != null &&
          DateTime.now().difference(_endedAtQueueTailAt!) <
              const Duration(seconds: 5);

      if (isTail && (isEndedLikeState || endedTailRecently)) {
        await seek(Duration.zero);
        try {
          await _startTransportPlay();
        } catch (e) {
          // Some transports can't resume from an ended source; reload the tail.
          _log('TailRestartPlayFailed: $e; reloading current index');
          await playFromQueueIndex(currentIdx, isAutoSkip: true, direction: 1);
        }
        return;
      }
      const threshold = Duration(seconds: 3);
      if (position > threshold) {
        // > 3s: restart the current song, ensuring playback if paused.
        await seek(Duration.zero);
        if (_userIntent == PlayIntent.play && !isPlayingNotifier.value) {
          await _startTransportPlay();
        }
      } else {
        await _stepToPreviousIndex();
      }
    } catch (e) {
      if (isTail) {
        // Some backends throw querying position right after end; reload tail.
        _log('Position unavailable at tail in previous(): $e; reloading tail');
        await playFromQueueIndex(currentIdx, isAutoSkip: true, direction: 1);
        return;
      }
      _log('Error getting position in previous(): $e');
      await _stepToPreviousIndex();
    }
  }

  _SelectionReason _classifySelection({
    required bool isAutoSkip,
    required bool respectPauseIntent,
    required int direction,
  }) {
    if (!isAutoSkip && !respectPauseIntent) return _SelectionReason.userTap;
    if (respectPauseIntent) return _SelectionReason.setQueue;
    if (!isAutoSkip) return _SelectionReason.other;
    return direction < 0
        ? _SelectionReason.previous
        : _SelectionReason.autoAdvance;
  }

  Future<void> playFromQueueIndex(
    int orderIndex, {
    bool isAutoSkip = false,
    bool respectPauseIntent = false,
    int direction = 1,
  }) async {
    final op = ++_opGeneration;
    _log(
      'playFromQueueIndex: idx=$orderIndex autoSkip=$isAutoSkip '
      'respectPause=$respectPauseIntent dir=$direction',
    );
    if (orderIndex < 0 || orderIndex >= _playlist.length) return;
    final track = _playlist.trackForOrderIndex(orderIndex);
    if (track == null) return;

    _lastSelectionReason = _classifySelection(
      isAutoSkip: isAutoSkip,
      respectPauseIntent: respectPauseIntent,
      direction: direction,
    );
    _lastSelectionDirection = direction == 0 ? 1 : direction.sign;

    // setQueue may respect a standing pause intent rather than start play.
    if (respectPauseIntent && _userIntent == PlayIntent.pause) {
      await _playlist.setCurrentOrderIndex(orderIndex);
      isPlayingNotifier.value = false;
      _emitSongInfo(force: true);
      return;
    }

    // Navigation/tap implies play; setQueue opts out via respectPauseIntent.
    if (!respectPauseIntent) _userIntent = PlayIntent.play;
    // Leaving the tail track clears the queue-end latch.
    if (orderIndex != _playlist.length - 1) _endedAtQueueTailAt = null;

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
    // URI schemes (content://, http(s)://) can't be preflighted via File.
    if (uri != null && uri.hasScheme) return false;
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

      // Skip known-failed tracks, except a direct user tap on the requested
      // track gets one retry (the file may have been restored).
      final isKnownFailed = _failedTrackPaths.contains(track.path);
      if (isKnownFailed &&
          !(reason == _SelectionReason.userTap && idx == startOrderIndex)) {
        _updateQueueWithNotFoundFlags();
        idx += dir;
        continue;
      }

      if (_shouldPreflightExists(track.path)) {
        final exists = await _fileExists(track.path);
        if (!exists) {
          _log('PreflightMissing: path=${track.path}');
          _recordError(track.path, 'preflight_missing', 'File does not exist');
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

      isPlayingNotifier.value = true; // Optimistic.
      _pendingLoadPath = track.path;
      _log('StartLoad: path=${track.path}');

      try {
        await _loadTrack(track);
        if (op != _opGeneration) return;
        _pendingLoadPath = null;
        _log('LoadSuccess: path=${track.path}');
        if (_failedTrackPaths.remove(track.path)) {
          _updateQueueWithNotFoundFlags();
        }
        _userIntent = PlayIntent.play;
        await _transport.play();
        if (op != _opGeneration) return;
        await _pauseIfIntentPause();
        _emitSongInfo(force: true);
        _preloadNext();
        return;
      } catch (e) {
        if (op != _opGeneration) return;
        _log('LoadError: path=${track.path} error=$e');
        final transient = _isTransientTransportError(e);
        _recordError(
          track.path,
          transient ? 'transport_load_transient' : 'transport_load_error',
          e.toString(),
        );

        // Transient: retry once briefly, then continue scanning.
        if (transient) {
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
            await _loadTrack(track);
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
              await _stopPlayback();
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

    // No playable tracks in the scan range.
    await _stopPlayback();
  }

  Future<void> seek(Duration position) async {
    await _transport.seek(position);
    _emitSongInfo();
  }

  /// Plays [track] standalone without mutating the queue. On natural end the
  /// queue is restored at the slot *after* the start position (or stops past
  /// the tail). Explicit prev/next exits; [repeatOne] loops in place.
  Future<void> playOneShot(AudioTrack track, {bool repeatOne = false}) async {
    final op = ++_opGeneration;

    // Capture queue position to restore later (null handled by _finishOneShot).
    _queueIndexAtOneShotStart = _playlist.currentOrderIndexNotifier.value;
    _oneShotTrack = track;
    _oneShotRepeatOne = repeatOne;
    _oneShot = true;
    isOneShotNotifier.value = true;
    _userIntent = PlayIntent.play;
    _endedAtQueueTailAt = null;
    _pendingLoadPath = track.path;
    _log('OneShot start: ${track.path} resumeAt=$_queueIndexAtOneShotStart');
    isPlayingNotifier.value = true;
    try {
      await _loadAndPlayOneShot(track, op);
    } catch (e) {
      _log('OneShot load failed: $e');
      _pendingLoadPath = null;
      // Abort and fall back to the queue at the captured index.
      _clearOneShot();
      await _stopPlayback();
    }
  }

  // Load [track], play it, and emit one-shot song info; throws on load failure.
  Future<void> _loadAndPlayOneShot(AudioTrack track, int op) async {
    await _loadTrack(track);
    if (op != _opGeneration) return;
    _pendingLoadPath = null;
    await _transport.play();
    if (op != _opGeneration) return;
    _emitOneShotSongInfo();
  }

  void _clearOneShot() {
    _oneShot = false;
    _oneShotTrack = null;
    _oneShotRepeatOne = false;
    _queueIndexAtOneShotStart = null;
    isOneShotNotifier.value = false;
  }

  Future<void> _restartOneShot() async {
    final track = _oneShotTrack;
    if (track == null) {
      _clearOneShot();
      return;
    }
    final op = ++_opGeneration;
    _pendingLoadPath = track.path;
    try {
      await _loadAndPlayOneShot(track, op);
    } catch (e) {
      _log('OneShot restart failed: $e');
      _pendingLoadPath = null;
      await _finishOneShot(manual: false);
    }
  }

  Future<void> _finishOneShot({
    required bool manual,
    bool backward = false,
  }) async {
    final resumeAt = _queueIndexAtOneShotStart;
    _clearOneShot();

    if (_playlist.length == 0 || resumeAt == null) {
      await _stopPlayback(resetIntent: true);
      return;
    }

    if (manual) {
      // Explicit prev/next: step from the captured position like normal nav.
      final target = (resumeAt + (backward ? -1 : 1))
          .clamp(0, _playlist.length - 1)
          .toInt();
      await playFromQueueIndex(
        target,
        isAutoSkip: true,
        direction: backward ? -1 : 1,
      );
      return;
    }

    // Natural end: advance to resumeAt + 1, or stop if past the tail.
    final next = resumeAt + 1;
    if (next >= _playlist.length) {
      await _stopPlayback(resetIntent: true);
      return;
    }
    await playFromQueueIndex(next, isAutoSkip: true, direction: 1);
  }

  /// Build a [SongInfo] for [track] from the transport's current position and
  /// duration and the current playing state.
  Future<SongInfo> _buildSongInfo(AudioTrack track) async {
    final position = await _transport.position;
    final duration = await _transport.duration;
    return SongInfo(
      track: track,
      isPlaying: isPlayingNotifier.value,
      position: position.inMilliseconds,
      duration: duration.inMilliseconds,
    );
  }

  Future<void> _emitOneShotSongInfo() async {
    final track = _oneShotTrack;
    if (track == null) return;
    songInfoNotifier.value = await _buildSongInfo(track);
  }

  /// Enter a search session (B-014). Snapshots queue + index on the FIRST enter
  /// only (re-entering just swaps results), installs [results] as the active
  /// queue, and plays [tappedIndex]. Restored by [exitSearchSession].
  Future<void> enterSearchSession(
    List<AudioTrack> results,
    int tappedIndex,
  ) async {
    if (results.isEmpty) return;
    final clampedTap = tappedIndex.clamp(0, results.length - 1).toInt();

    if (_activeSearchSession == null) {
      // Snapshot the raw queue (no isNotFound flags) for a faithful restore.
      final savedQueue = List<AudioTrack>.unmodifiable(
        _playlist.queueNotifier.value,
      );
      final savedIndex = _playlist.currentOrderIndexNotifier.value ?? 0;
      _activeSearchSession = _SearchSession(
        savedQueue: savedQueue,
        savedIndex: savedIndex,
      );
      _log('SearchSession enter: index=$savedIndex len=${savedQueue.length}');
    } else {
      _log('SearchSession re-enter (no re-snapshot)');
    }

    // Reuse setQueue for load/intent/error handling; shuffle:false keeps order.
    await setQueue(results, startIndex: clampedTap, shuffle: false);
  }

  /// Exit the search session (B-014). Restores the original queue + index
  /// WITHOUT reloading the transport (playing track keeps playing); prefers the
  /// playing track's position, else the snapshot. No-op if no session active.
  Future<void> exitSearchSession() async {
    final session = _activeSearchSession;
    if (session == null) return;
    _activeSearchSession = null;

    final currentIdx = _playlist.currentOrderIndexNotifier.value;
    final activeTrack = currentIdx == null
        ? null
        : _playlist.trackForOrderIndex(currentIdx);

    // Prior queue was emptied — restore as empty (no reload).
    if (session.savedQueue.isEmpty) {
      await _playlist.setQueue(const <AudioTrack>[]);
      _failedTrackPaths.clear();
      _updateQueueWithNotFoundFlags();
      _log('SearchSession exit: restored empty queue');
      return;
    }

    // Prefer the playing track's position so displayed info matches audio.
    var restoreIndex = session.savedIndex;
    if (activeTrack != null) {
      final idxInRestored = session.savedQueue.indexWhere(
        (t) => t.path == activeTrack.path,
      );
      if (idxInRestored >= 0) restoreIndex = idxInRestored;
    }
    restoreIndex = restoreIndex.clamp(0, session.savedQueue.length - 1).toInt();

    // Failed markers belonged to result tracks, not the original queue.
    _failedTrackPaths.clear();
    // Restore via the playlist directly so the transport is NOT reloaded.
    await _playlist.setQueue(session.savedQueue, startBaseIndex: restoreIndex);
    _updateQueueWithNotFoundFlags();
    _log(
      'SearchSession exit: len=${session.savedQueue.length} '
      'index=$restoreIndex active=${activeTrack?.path ?? "null"}',
    );
    await _emitSongInfo(force: true);
  }

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    _failedTrackPaths.clear();
    // Set intent BEFORE any await so a concurrent playPause can cancel it.
    if (tracks.isNotEmpty) _userIntent = PlayIntent.play;

    await _playlist.setQueue(
      tracks,
      startBaseIndex: startIndex,
      enableShuffle: shuffle,
    );
    _endedAtQueueTailAt = null;
    _updateQueueWithNotFoundFlags();

    if (tracks.isNotEmpty) {
      final initialIndex = _playlist.currentOrderIndexNotifier.value ?? 0;
      await playFromQueueIndex(
        initialIndex,
        respectPauseIntent: true,
        direction: 1,
      );

      // User may have paused during load.
      await _pauseIfIntentPause();
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

  /// Keep playback running without reloading when [wasPlaying].
  Future<void> _resumeIfWasPlaying(bool wasPlaying) async {
    if (!wasPlaying) return;
    if (!isPlayingNotifier.value) {
      await _transport.play();
      isPlayingNotifier.value = true;
    }
    _emitSongInfo();
  }

  /// Apply a shuffle-mode change that reorders the queue around the current
  /// track without reloading: run [reorder] with the current base index, refresh
  /// the not-found mirror, then resume playback if it was playing.
  Future<void> _applyShuffleChange(
    Future<void> Function(int keepBaseIndex) reorder,
  ) async {
    final baseIndex = _playlist.currentBaseIndex ?? 0;
    final wasPlaying = _userIntent == PlayIntent.play;
    await reorder(baseIndex);
    _updateQueueWithNotFoundFlags();
    await _resumeIfWasPlaying(wasPlaying);
  }

  Future<void> shuffleQueue() => _applyShuffleChange(
    (keepBaseIndex) => _playlist.reshuffle(keepBaseIndex: keepBaseIndex),
  );

  Future<void> disableShuffle() => _applyShuffleChange(
    (keepBaseIndex) => _playlist.disableShuffle(keepBaseIndex: keepBaseIndex),
  );

  Future<void> _emitSongInfo({bool force = false}) async {
    if (_oneShot) {
      await _emitOneShotSongInfo();
      return;
    }
    final track = _currentTrack;
    if (track == null) {
      if (force || songInfoNotifier.value != null) {
        songInfoNotifier.value = null;
      }
      return;
    }

    // End-of-track advance is handled via TransportEndedEvent, not here (races).
    final nextSongInfo = await _buildSongInfo(track);

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

  Future<int> playlistSizeBytes() => _playlist.persistentSizeBytes();

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
        // Fall back to filename on extraction failure.
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
    // JustAudio "Connection aborted" / 10000000 from rapid track changes or
    // codec re-init; transient.
    final s = error.toString().toLowerCase();
    return s.contains('connection aborted') || s.contains('10000000');
  }

  /// Structured snapshot of controller state for debugging / emulator tooling.
  Map<String, Object?> diagnosticsSnapshot() {
    final idx = _playlist.currentOrderIndexNotifier.value;
    return <String, Object?>{
      'userIntent': _userIntent.name,
      'isPlaying': isPlayingNotifier.value,
      'currentOrderIndex': idx,
      'currentPath': _currentTrack?.path,
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
      'audioEvents': List<String>.unmodifiable(_audioEvents),
    };
  }

  /// Audio-event ring buffer (interruption / route / load / error).
  List<String> audioEvents() => List<String>.unmodifiable(_audioEvents);
}
