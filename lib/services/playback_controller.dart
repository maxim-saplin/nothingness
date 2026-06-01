import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/audio_track.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import 'audio_transport.dart';
import 'playback/playback_bloc.dart';
import 'spectrum_source.dart';
import 'metadata_extractor.dart';
import 'playback_telemetry.dart';
import 'playlist_store.dart';
import 'soloud_transport.dart';

/// The user's explicit intent for playback state.
enum PlayIntent { play, pause }

/// Single source of truth for playback: user intent, queue, error recovery,
/// and coordination with the [AudioTransport]. Also the UI-facing
/// [ChangeNotifier] — its sub-notifiers (song info, play state, queue, index,
/// shuffle, one-shot) and the spectrum stream are fanned into [notifyListeners]
/// so widgets can `context.watch<PlaybackController>()` directly.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required AudioTransport transport,
    PlaylistStore? playlist,
    this.debugPlaybackLogs = false,
    this.captureRecentLogs = false,
    this.recentLogCapacity = 50,
    Duration navSettleDelay = const Duration(milliseconds: 250),
  })  : _navSettleDelay = navSettleDelay,
        _transport = transport,
        _playlist = playlist ?? PlaylistStore(),
        _supportedExtensions = _getSupportedExtensions(transport) {
    _telemetry = PlaybackTelemetry(
      captureRecentLogs: captureRecentLogs,
      recentLogCapacity: recentLogCapacity,
      debugPlaybackLogs: debugPlaybackLogs,
    );
    _bloc = PlaybackBloc(
      transport: _transport,
      playlist: _playlist,
      navSettleDelay: _navSettleDelay,
      onLog: _telemetry.log,
    );
  }

  final Duration _navSettleDelay;
  late final PlaybackTelemetry _telemetry;
  late final PlaybackBloc _bloc;
  StreamSubscription<PbState>? _blocSub;

  final AudioTransport _transport;
  final PlaylistStore _playlist;
  final bool debugPlaybackLogs;
  final bool captureRecentLogs;
  final int recentLogCapacity;
  final Set<String> _supportedExtensions;

  final ValueNotifier<SongInfo?> songInfoNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isOneShotNotifier = ValueNotifier(false);
  final ValueNotifier<List<AudioTrack>> queueNotifier = ValueNotifier(const []);

  PlayIntent _userIntent = PlayIntent.pause;
  PlayIntent get userIntent => _userIntent;

  ValueNotifier<int?> get currentIndexNotifier =>
      _playlist.currentOrderIndexNotifier;
  ValueNotifier<bool> get shuffleNotifier => _playlist.shuffleNotifier;

  // ---- UI-facing getters (ChangeNotifier surface) ---------------------------

  SongInfo? get songInfo => songInfoNotifier.value;
  bool get isPlaying => isPlayingNotifier.value;
  List<AudioTrack> get queue => queueNotifier.value;
  int? get currentIndex => currentIndexNotifier.value;
  bool get shuffle => shuffleNotifier.value;

  /// Supported file extensions for the active transport's decoder.
  static Set<String> get supportedExtensions =>
      SoLoudTransport.supportedExtensions;

  // ---- Spectrum facade — state/lifecycle live in [SpectrumSource] ----------

  // NOT fanned into notifyListeners: the spectrum ticks at ~60fps and doing so
  // rebuilt every `context.watch<PlaybackController>()` widget every frame (the
  // hero/transport rebuild storm). Visualizers listen to [spectrumListenable]
  // directly (RepaintBoundary-isolated) so only they repaint per frame.
  late final SpectrumSource _spectrum = SpectrumSource(_transport);

  List<double> get spectrumData => _spectrum.data;
  /// Ticks per spectrum frame — for the visualizer's isolated repaint only.
  Listenable get spectrumListenable => _spectrum;
  Stream<List<double>> get spectrumStream => _spectrum.stream;
  void setCaptureEnabled(bool enabled) => _spectrum.setCaptureEnabled(enabled);
  void updateSpectrumSettings(SpectrumSettings settings) =>
      _spectrum.updateSettings(settings);

  // Fan every sub-notifier into [notifyListeners]; wired in [init], torn down in
  // [dispose].
  late final List<Listenable> _uiNotifiers = <Listenable>[
    songInfoNotifier,
    isPlayingNotifier,
    isOneShotNotifier,
    queueNotifier,
    currentIndexNotifier,
    shuffleNotifier,
  ];
  bool _uiWired = false;
  void _notify() => notifyListeners();

  // One-shot (a track played outside the queue) now lives in the bloc — one
  // engine, no parallel controller path.
  bool get isOneShot => _bloc.isOneShot;
  AudioTrack? get oneShotTrack => _bloc.oneShotTrack;

  // Search-session state (B-014): original queue/index preserved for restore.
  // Snapshot taken on first enter only; null when no session is active.
  List<AudioTrack>? _savedQueue;
  int _savedIndex = 0;
  bool get isInSearchSession => _savedQueue != null;

  // Bumped by every explicit user intent command (play/pause/next/previous).
  // A long-running op (e.g. folder reshuffle) captures this before its awaits;
  // if it changed by the time the op lands, the user acted meanwhile, so the op
  // must not clobber the newer intent (B: pause-then-it-plays-anyway).
  int _userActionGen = 0;
  int get userActionGen => _userActionGen;
  StreamSubscription<TransportEvent>? _transportEventSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesSub;
  Timer? _positionTimer;

  /// Recent controller logs (if enabled), for test/diagnostics.
  List<String> recentLogs() => _telemetry.recentLogs;

  /// Audio-event ring buffer (interruption / route / load / error).
  List<String> audioEvents() => _telemetry.audioEvents;

  Future<void> _loadTrack(AudioTrack track) =>
      _transport.load(track.path, title: track.title, artist: track.artist);

  // The track at the current order index, or null if none is selected.
  AudioTrack? get _currentTrack {
    final idx = _playlist.currentOrderIndexNotifier.value;
    return idx == null ? null : _playlist.trackForOrderIndex(idx);
  }

  Future<void> init() async {
    await _playlist.init();
    await _transport.init();

    _transportEventSub = _transport.eventStream.listen(_handleTransportEvent);
    _blocSub = _bloc.stream.listen(_onBlocState);
    _telemetry.log('Initialized: subscribed to transport events');

    // Audio focus / interruption events; unavailable in some test/host envs.
    try {
      final session = await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen(_onInterruption);
      _noisySub =
          session.becomingNoisyEventStream.listen((_) => _onBecomingNoisy());
      _devicesSub = session.devicesChangedEventStream.listen(_onDevicesChanged);
      _telemetry.log('Initialized: subscribed to audio session events');
    } catch (e) {
      _telemetry.log('AudioSession unavailable: $e');
    }

    _playlist.queueNotifier.addListener(_updateQueueWithNotFoundFlags);
    _playlist.currentOrderIndexNotifier.addListener(_onIndexChanged);
    _playlist.shuffleNotifier.addListener(_updateQueueWithNotFoundFlags);

    _positionTimer = _newPositionTimer();
    _updateQueueWithNotFoundFlags();

    // Fan sub-notifier changes into ChangeNotifier listeners + mirror spectrum.
    if (!_uiWired) {
      _uiWired = true;
      for (final n in _uiNotifiers) {
        n.addListener(_notify);
      }
      _spectrum.start();
    }

    final track = _currentTrack;
    final idx = _playlist.currentOrderIndexNotifier.value;
    if (track != null && idx != null) {
      try {
        await _loadTrack(track); // load for display (paused) on restore
      } catch (e) {
        // Ignore startup load errors; handled when the user tries to play.
        debugPrint('Failed to load initial track: $e');
      }
      _bloc.add(AdoptCurrent(idx, playing: false));
    }
    await _emitSongInfo(force: true);
  }

  // Mirror the bloc's authoritative state into the UI-facing notifiers.
  void _onBlocState(PbState s) {
    // Queue-end resets intent to pause so the play button reacts; otherwise the
    // controller's command methods own _userIntent.
    if (s is PbStopped) _userIntent = PlayIntent.pause;
    isPlayingNotifier.value = s.isPlaying;
    isOneShotNotifier.value = _bloc.isOneShot;
    _updateQueueWithNotFoundFlags();
    // Flip the hero title/artist SYNCHRONOUSLY from the state's track (already
    // carried by PbLoading/PbActive — queue OR one-shot) so names cycle at 60fps
    // on a tap burst, never gated on the transport. Position/duration refine
    // just below.
    _emitSongInfoSync(s);
    unawaited(_emitSongInfo(force: true));
  }

  // Instant, transport-free hero update from the bloc state. For a new track,
  // position resets to 0 and duration uses the cached tag (if any); for the same
  // track (e.g. pause↔resume) the current position/duration are preserved so the
  // progress bar doesn't flicker.
  void _emitSongInfoSync(PbState s) {
    final track = s.track;
    if (track == null) return; // PbStopped: leave to _emitSongInfo
    final current = songInfoNotifier.value;
    final sameTrack = current != null && current.track.path == track.path;
    songInfoNotifier.value = SongInfo(
      track: track,
      isPlaying: s.isPlaying,
      position: sameTrack ? current.position : 0,
      duration: sameTrack ? current.duration : (track.duration?.inMilliseconds ?? 0),
    );
  }

  // Await the bloc converging to a stable (non-Loading) state after a command,
  // so `await next()/playPause()` etc. still settle on the played track. A no-op
  // command (already-stable, nothing emitted) falls through the timeout.
  Future<void> _settle() async {
    try {
      await _bloc.stream
          .firstWhere((s) => s is PbActive || s is PbStopped)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
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

  // Detaches listeners/timers synchronously (ChangeNotifier contract) and
  // kicks off async resource teardown, exposed via [_teardown] for [shutdown].
  Future<void>? _teardown;

  @override
  void dispose() {
    _positionTimer?.cancel();
    _positionTimer = null;
    if (_uiWired) {
      _uiWired = false;
      for (final n in _uiNotifiers) {
        n.removeListener(_notify);
      }
    }
    _playlist.queueNotifier.removeListener(_updateQueueWithNotFoundFlags);
    _playlist.currentOrderIndexNotifier.removeListener(_onIndexChanged);
    _playlist.shuffleNotifier.removeListener(_updateQueueWithNotFoundFlags);
    _teardown ??= _disposeAsync();
    super.dispose();
  }

  // Cancels subscriptions and disposes the transport + playlist. Awaitable via
  // [shutdown] so callers/tests can flush the playlist box before exiting.
  Future<void> _disposeAsync() async {
    _spectrum.dispose();
    await _blocSub?.cancel();
    await _bloc.close();
    await _transportEventSub?.cancel();
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    await _devicesSub?.cancel();
    await _transport.dispose();
    await _playlist.dispose();
  }

  /// Synchronous [dispose] plus the awaitable async teardown (transport +
  /// playlist). Prefer this where the caller can await (e.g. tests, hot-restart).
  Future<void> shutdown() async {
    if (_teardown == null) dispose();
    await _teardown;
  }

  void _onIndexChanged() {
    _updateQueueWithNotFoundFlags();
    _emitSongInfo();
  }

  void _updateQueueWithNotFoundFlags() {
    final failed = _bloc.failedPaths;
    queueNotifier.value = [
      for (final t in _playlist.queueNotifier.value)
        failed.contains(t.path) ? t.copyWith(isNotFound: true) : t,
    ];
  }

  // ---- Audio session events -------------------------------------------------

  void _onInterruption(AudioInterruptionEvent event) {
    _telemetry.event('interruption', {'begin': event.begin, 'type': event.type.name});
    _bloc.add(event.begin
        ? InterruptionBegan(event.type)
        : InterruptionEnded(event.type));
  }

  void _onBecomingNoisy() {
    _telemetry.event('becomingNoisy');
    _userIntent = PlayIntent.pause; // headphones yanked = explicit pause
    _bloc.add(const BecameNoisy());
  }

  void _onDevicesChanged(AudioDevicesChangedEvent event) {
    String outputs(Iterable<AudioDevice> devices) => devices
        .where((d) => d.isOutput)
        .map((d) => '${d.type.name}:${d.name}')
        .join(',');
    final added = outputs(event.devicesAdded);
    final removed = outputs(event.devicesRemoved);
    if (added.isEmpty && removed.isEmpty) return;
    _telemetry.event('devicesChanged', {'added': added, 'removed': removed});
  }

  /// Debug seam for tests / `ext.nothingness.simulateInterruption`.
  void debugSimulateInterruption(AudioInterruptionEvent event) =>
      _onInterruption(event);

  /// Debug seam for tests / `ext.nothingness.simulateNoisy`.
  void debugSimulateBecomingNoisy() => _onBecomingNoisy();

  // ---- Transport events -----------------------------------------------------

  void _handleTransportEvent(TransportEvent event) {
    switch (event) {
      case TransportErrorEvent(:final path):
        _telemetry.log('Event ERROR path=${path ?? 'null'}');
        _handleTrackError(path);
      case TransportEndedEvent(:final path):
        _telemetry.log('Event ENDED path=${path ?? 'null'}');
        _handleTrackEnded(path);
      case TransportLoadedEvent(:final path):
        _telemetry.log('Event LOADED path=${path ?? 'null'}');
        _onTrackLoaded(path);
      case TransportPositionEvent():
        break; // Handled by the timer.
    }
  }

  void _handleTrackError(String? path) {
    if (path == null) return;
    // The bloc's load() catch owns failed-marking + skip; _onBlocState then
    // refreshes the not-found flags. Nothing to do here but record it.
    _telemetry.event('transportError', {'path': path});
  }

  void _handleTrackEnded(String? path) {
    _telemetry.event('transportEnded', {'path': path ?? ''});
    // Queue auto-advance, one-shot resume, and B-036 dedup all live in the bloc.
    _bloc.add(TrackEnded(path));
  }

  void _onTrackLoaded(String? path) {
    if (path == null) return;
    _telemetry.event('transportLoaded', {'path': path});
    _updateQueueWithNotFoundFlags();
    _emitSongInfo(force: true);
  }

  // ---- Public transport controls --------------------------------------------

  Future<void> playPause() async {
    _userActionGen++;
    if (_playlist.length == 0 && !isOneShot) return;
    // Toggle our authoritative intent and tell the bloc explicitly (so a
    // setQueue/load race can't lose the user's pause). The bloc toggles whatever
    // is current — queue track or one-shot — in place.
    _userIntent =
        _userIntent == PlayIntent.play ? PlayIntent.pause : PlayIntent.play;
    _bloc.add(SetIntent(_userIntent == PlayIntent.play));
    await _settle();
  }

  Future<void> next() async {
    _userActionGen++;
    // Queue tail doesn't wrap; but during one-shot, next always exits to the
    // queue (the bloc handles it).
    if (!isOneShot && _playlist.nextOrderIndex() == null) return;
    _userIntent = PlayIntent.play;
    _bloc.add(const GoNext());
    await _settle();
  }

  Future<void> previous() async {
    _userActionGen++;
    if (!isOneShot &&
        _playlist.currentOrderIndexNotifier.value == null &&
        _playlist.previousOrderIndex() == null) {
      return;
    }
    _userIntent = PlayIntent.play;
    _bloc.add(const GoPrevious());
    await _settle();
  }

  Future<void> seek(Duration position) async {
    await _transport.seek(position);
    _emitSongInfo();
  }

  Future<void> playFromQueueIndex(
    int orderIndex, {
    bool isAutoSkip = false,
    bool respectPauseIntent = false,
    int direction = 1,
  }) async {
    if (orderIndex < 0 || orderIndex >= _playlist.length) return;
    if (_playlist.trackForOrderIndex(orderIndex) == null) return;
    final intentPlay = !(respectPauseIntent && _userIntent == PlayIntent.pause);
    _userIntent = intentPlay ? PlayIntent.play : PlayIntent.pause;
    _bloc.add(GoToIndex(
      orderIndex,
      intentPlay: intentPlay,
      direction: direction,
      userTap: !isAutoSkip && !respectPauseIntent,
      respectPauseIntent: respectPauseIntent,
    ));
    await _settle();
  }

  // ---- One-shot -------------------------------------------------------------

  /// Plays [track] standalone (not in the queue) via the bloc. On natural end
  /// the queue resumes at the captured slot + 1 (or stops past the tail);
  /// explicit next/previous exits; [repeatOne] loops in place.
  Future<void> playOneShot(AudioTrack track, {bool repeatOne = false}) async {
    _userActionGen++;
    _userIntent = PlayIntent.play;
    _bloc.add(PlayOneShot(track, repeatOne: repeatOne));
    await _settle();
  }

  // ---- Song info ------------------------------------------------------------

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

  Future<void> _emitSongInfo({bool force = false}) async {
    // The bloc state's track is authoritative (queue OR one-shot); fall back to
    // the playlist's current track only when idle/stopped.
    final track = _bloc.state.track ?? _currentTrack;
    if (track == null) {
      if (force || songInfoNotifier.value != null) songInfoNotifier.value = null;
      return;
    }

    // End-of-track advance is handled via TransportEndedEvent, not here (races).
    final next = await _buildSongInfo(track);
    final current = songInfoNotifier.value;
    if (!force &&
        current != null &&
        current.track.path == next.track.path &&
        current.isPlaying == next.isPlaying &&
        current.position == next.position &&
        current.duration == next.duration) {
      return;
    }
    songInfoNotifier.value = next;
  }

  // ---- Search session (B-014) -----------------------------------------------

  /// Enter a search session. Snapshots queue + index on the FIRST enter only
  /// (re-entering just swaps results), installs [results] as the active queue,
  /// and plays [tappedIndex]. Restored by [exitSearchSession].
  Future<void> enterSearchSession(
    List<AudioTrack> results,
    int tappedIndex,
  ) async {
    if (results.isEmpty) return;
    final clampedTap = tappedIndex.clamp(0, results.length - 1).toInt();

    if (_savedQueue == null) {
      // Snapshot the raw queue (no isNotFound flags) for a faithful restore.
      _savedQueue =
          List<AudioTrack>.unmodifiable(_playlist.queueNotifier.value);
      _savedIndex = _playlist.currentOrderIndexNotifier.value ?? 0;
      _telemetry.log('SearchSession enter: index=$_savedIndex len=${_savedQueue!.length}');
    } else {
      _telemetry.log('SearchSession re-enter (no re-snapshot)');
    }

    // Reuse setQueue for load/intent/error handling; shuffle:false keeps order.
    await setQueue(results, startIndex: clampedTap, shuffle: false);
  }

  /// Exit the search session. Restores the original queue + index WITHOUT
  /// reloading the transport (playing track keeps playing); prefers the playing
  /// track's position, else the snapshot. No-op if no session active.
  Future<void> exitSearchSession() async {
    final savedQueue = _savedQueue;
    if (savedQueue == null) return;
    final savedIndex = _savedIndex;
    _savedQueue = null;

    final currentIdx = _playlist.currentOrderIndexNotifier.value;
    final activeTrack =
        currentIdx == null ? null : _playlist.trackForOrderIndex(currentIdx);

    // Failed markers belonged to result tracks, not the original queue.
    _bloc.clearFailed();

    if (savedQueue.isEmpty) {
      // Prior queue was emptied — restore as empty (no reload).
      await _playlist.setQueue(const <AudioTrack>[]);
      _updateQueueWithNotFoundFlags();
      _telemetry.log('SearchSession exit: restored empty queue');
      return;
    }

    // Prefer the playing track's position so displayed info matches audio.
    var restoreIndex = savedIndex;
    if (activeTrack != null) {
      final idxInRestored =
          savedQueue.indexWhere((t) => t.path == activeTrack.path);
      if (idxInRestored >= 0) restoreIndex = idxInRestored;
    }
    restoreIndex = restoreIndex.clamp(0, savedQueue.length - 1).toInt();

    // Restore via the playlist directly so the transport is NOT reloaded; the
    // bloc adopts the still-playing track as its active state (no reload).
    await _playlist.setQueue(savedQueue, startBaseIndex: restoreIndex);
    _bloc.add(AdoptCurrent(_playlist.currentOrderIndexNotifier.value ?? restoreIndex,
        playing: isPlayingNotifier.value));
    _updateQueueWithNotFoundFlags();
    _telemetry.log('SearchSession exit: len=${savedQueue.length} '
        'index=$restoreIndex active=${activeTrack?.path ?? "null"}');
    await _emitSongInfo(force: true);
  }

  // ---- Queue mutation -------------------------------------------------------

  /// Replaces the queue and (normally) starts playback. [guardActionGen] lets a
  /// long-running caller (folder reshuffle) pass the [userActionGen] it captured
  /// before its slow load; if the user has since issued an intent command (e.g.
  /// tapped pause), the queue is still set but we DON'T force play — the newer
  /// intent wins (fixes "pause, pocket the phone, it plays anyway").
  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
    int? guardActionGen,
  }) async {
    _bloc.clearFailed();
    final superseded = guardActionGen != null && _userActionGen != guardActionGen;
    // Set intent BEFORE any await so a concurrent playPause can cancel it —
    // unless a user command already landed during the caller's load.
    if (tracks.isNotEmpty && !superseded) _userIntent = PlayIntent.play;

    await _playlist.setQueue(tracks,
        startBaseIndex: startIndex, enableShuffle: shuffle);
    _updateQueueWithNotFoundFlags();

    if (tracks.isNotEmpty) {
      final initialIndex = _playlist.currentOrderIndexNotifier.value ?? 0;
      // respectPauseIntent: a standing pause (incl. one the user made during a
      // superseded folder load) keeps the new queue loaded but paused.
      await playFromQueueIndex(initialIndex,
          respectPauseIntent: true, direction: 1);
    }
  }

  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false}) async {
    await _playlist.addTracks(tracks);
    _updateQueueWithNotFoundFlags();

    if (play && tracks.isNotEmpty) {
      final firstNewBaseIndex = _playlist.baseLength - tracks.length;
      final orderIndex = _playlist.orderIndexForBase(firstNewBaseIndex) ??
          _playlist.length - 1;
      await playFromQueueIndex(orderIndex, isAutoSkip: true);
    }
  }

  // ---- Shuffle --------------------------------------------------------------

  /// Apply a shuffle-mode change that reorders the queue around the current
  /// track without reloading: run [reorder] with the current base index,
  /// refresh the not-found mirror, then resume playback if it was playing.
  Future<void> _applyShuffleChange(
    Future<void> Function(int keepBaseIndex) reorder,
  ) async {
    final baseIndex = _playlist.currentBaseIndex ?? 0;
    final wasPlaying = _userIntent == PlayIntent.play;
    await reorder(baseIndex);
    _updateQueueWithNotFoundFlags();
    if (wasPlaying && !isPlayingNotifier.value) {
      await _transport.play();
      isPlayingNotifier.value = true;
    }
    if (wasPlaying) _emitSongInfo();
  }

  Future<void> shuffleQueue() => _applyShuffleChange(
      (keepBaseIndex) => _playlist.reshuffle(keepBaseIndex: keepBaseIndex));

  Future<void> disableShuffle() => _applyShuffleChange(
      (keepBaseIndex) => _playlist.disableShuffle(keepBaseIndex: keepBaseIndex));

  // ---- Library / diagnostics ------------------------------------------------

  Future<int> playlistSizeBytes() => _playlist.persistentSizeBytes();

  Future<List<AudioTrack>> scanFolder(String rootPath) async {
    final tracks = <AudioTrack>[];
    final directory = Directory(rootPath);
    if (!await directory.exists()) return tracks;
    final extractor = createMetadataExtractor();

    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).replaceAll('.', '').toLowerCase();
      if (!_supportedExtensions.contains(ext)) continue;
      try {
        tracks.add(await extractor.extractMetadata(entity.path));
      } catch (e) {
        // Fall back to filename on extraction failure.
        tracks.add(AudioTrack(
            path: entity.path,
            title: p.basenameWithoutExtension(entity.path)));
      }
    }
    tracks.sort((a, b) => a.title.compareTo(b.title));
    return tracks;
  }

  static Set<String> _getSupportedExtensions(AudioTransport transport) {
    if (transport is SoLoudTransport) return SoLoudTransport.supportedExtensions;
    return const {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus'};
  }

  /// Structured snapshot of controller state for debugging / emulator tooling.
  Map<String, Object?> diagnosticsSnapshot() {
    final err = _bloc.lastError;
    return <String, Object?>{
      'userIntent': _userIntent.name,
      'isPlaying': isPlayingNotifier.value,
      'currentOrderIndex': _playlist.currentOrderIndexNotifier.value,
      'currentPath': _currentTrack?.path,
      'queueLength': _playlist.length,
      'failedTrackPaths': _bloc.failedPaths.toList()..sort(),
      'pendingLoadPath': null,
      'lastSelectionReason': 'other',
      'lastSelectionDirection': 1,
      'lastError': <String, Object?>{
        'path': err?.path,
        'reason': err?.reason,
        'message': err?.message,
      },
      'recentLogs': recentLogs(),
      'audioEvents': _telemetry.audioEvents,
    };
  }
}
