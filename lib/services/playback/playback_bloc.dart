import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';

import '../../models/audio_track.dart';
import '../audio_transport.dart';
import '../playlist_store.dart';

/// A load failure that may resolve on retry (vs. a definitively missing/
/// unreadable track). Shared by the bloc's queue recovery and the controller's
/// one-shot path so both classify failures identically.
bool isTransientLoadError(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('connection aborted') || s.contains('10000000');
}

// ---------------------------------------------------------------------------
// State — an explicit, sealed machine. Exhaustive `switch`es make every
// state×event combination compiler-checked; the in-flight track lives IN the
// state (PbLoading.track), so a stale load completion is structurally ignored.
// ---------------------------------------------------------------------------

sealed class PbState {
  const PbState();
  int? get index;
  AudioTrack? get track => null;
  bool get isPlaying => false;
}

/// Nothing is playing (idle, queue-empty, or queue finished). [index] is kept
/// so pressing play can restart the last track.
final class PbStopped extends PbState {
  const PbStopped({this.index});
  @override
  final int? index;
}

/// A track is being loaded; [intentPlay] is what to do once it lands.
final class PbLoading extends PbState {
  const PbLoading({required this.index, required AudioTrack track, required this.intentPlay})
      : _track = track;
  @override
  final int index;
  final AudioTrack _track;
  final bool intentPlay;
  @override
  AudioTrack get track => _track;
  @override
  bool get isPlaying => intentPlay; // optimistic until the load settles
}

/// A track is loaded and either playing or paused.
final class PbActive extends PbState {
  const PbActive({required this.index, required AudioTrack track, required this.playing})
      : _track = track;
  @override
  final int index;
  final AudioTrack _track;
  final bool playing;
  @override
  AudioTrack get track => _track;
  @override
  bool get isPlaying => playing;
}

// ---------------------------------------------------------------------------
// Events. Commands share one base so a single restartable handler supersedes
// any in-flight command (latest-wins). Transport/system events are sequential.
// ---------------------------------------------------------------------------

sealed class PbEvent {
  const PbEvent();
}

/// User/queue commands — processed by the single restartable handler.
sealed class PbCommand extends PbEvent {
  const PbCommand();
}

final class TogglePlayPause extends PbCommand {
  const TogglePlayPause();
}

/// Set the desired play/pause intent explicitly (the owner toggles its own
/// authoritative intent and sends the result here). play=true resumes/loads;
/// play=false pauses — without changing the track.
final class SetIntent extends PbCommand {
  const SetIntent(this.play);
  final bool play;
}

final class GoNext extends PbCommand {
  const GoNext();
}

final class GoPrevious extends PbCommand {
  const GoPrevious();
}

/// Play a specific order index. [respectPauseIntent] (setQueue) keeps a standing
/// pause; [userTap] grants the requested track one retry even if marked failed.
final class GoToIndex extends PbCommand {
  const GoToIndex(this.index,
      {this.intentPlay = true,
      this.direction = 1,
      this.userTap = false,
      this.respectPauseIntent = false});
  final int index;
  final bool intentPlay;
  final int direction;
  final bool userTap;
  final bool respectPauseIntent;
}

final class SeekTo extends PbCommand {
  const SeekTo(this.position);
  final Duration position;
}

/// Play [track] standalone (NOT in the queue). The queue index at the time is
/// captured; on natural end it resumes at captured+1 (or stops past the tail).
/// Explicit next/previous exits to the queue; [repeatOne] loops in place.
final class PlayOneShot extends PbCommand {
  const PlayOneShot(this.track, {this.repeatOne = false});
  final AudioTrack track;
  final bool repeatOne;
}

/// Adopt the already-playing track at [index] as the active state WITHOUT
/// reloading the transport — used to restore a queue (e.g. search-session exit)
/// while audio keeps playing.
final class AdoptCurrent extends PbEvent {
  const AdoptCurrent(this.index, {required this.playing});
  final int index;
  final bool playing;
}

final class TrackEnded extends PbEvent {
  const TrackEnded(this.path);
  final String? path;
}

final class InterruptionBegan extends PbEvent {
  const InterruptionBegan(this.type);
  final AudioInterruptionType type;
}

final class InterruptionEnded extends PbEvent {
  const InterruptionEnded(this.type);
  final AudioInterruptionType type;
}

final class BecameNoisy extends PbEvent {
  const BecameNoisy();
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

/// Serialized, sealed playback state machine. Owns the transport + playlist
/// navigation; emits [PbState] the UI/controller maps to notifiers.
class PlaybackBloc extends Bloc<PbEvent, PbState> {
  PlaybackBloc({
    required AudioTransport transport,
    required PlaylistStore playlist,
    this.transientRetryDelay = const Duration(milliseconds: 200),
    this.navSettleDelay = Duration.zero,
    void Function(String)? onLog,
  })  : _transport = transport,
        _playlist = playlist,
        _log = onLog ?? _noLog,
        super(const PbStopped()) {
    // One restartable handler for ALL commands → a newer command cancels the
    // in-flight one (latest command wins) with no manual generation tracking.
    on<PbCommand>(_onCommand, transformer: restartable());
    on<TrackEnded>(_onEnded, transformer: sequential());
    on<InterruptionBegan>(_onInterruptionBegan, transformer: sequential());
    on<InterruptionEnded>(_onInterruptionEnded, transformer: sequential());
    on<BecameNoisy>(_onNoisy, transformer: sequential());
    on<AdoptCurrent>(_onAdopt, transformer: sequential());
    // The owner (PlaybackController) arbitrates transport events — it feeds
    // [TrackEnded] for queue tracks (and handles one-shot ends itself) — so the
    // bloc doesn't subscribe to the transport stream directly.
  }

  final AudioTransport _transport;
  final PlaylistStore _playlist;
  final Duration transientRetryDelay;
  // How long Next/Previous waits (for further taps) before loading. The current
  // track keeps playing during this window, so rapid nav cycles song NAMES at
  // 60fps while audio only switches to the track you land on. 0 = load at once.
  final Duration navSettleDelay;
  final void Function(String) _log;

  static void _noLog(String _) {}

  final Set<String> _failedPaths = <String>{};
  bool _pausedByInterruption = false;

  // One-shot: a track played outside the queue. [_oneShotResume] is the queue
  // slot to return to when it ends. One engine, no parallel controller path.
  AudioTrack? _oneShotTrack;
  int? _oneShotResume;
  bool _oneShotRepeat = false;
  bool get isOneShot => _oneShotTrack != null;
  AudioTrack? get oneShotTrack => _oneShotTrack;
  int _transientCount = 0;
  DateTime? _transientWindowStart;

  // Last load failure, surfaced for the controller's diagnostics snapshot.
  ({String path, String reason, String message})? lastError;

  Set<String> get failedPaths => Set.unmodifiable(_failedPaths);

  /// Clear failed-track flags + last error (e.g. on a fresh queue).
  void clearFailed() {
    _failedPaths.clear();
    lastError = null;
  }

  // ---- command handler (restartable) ---------------------------------------

  Future<void> _onCommand(PbCommand event, Emitter<PbState> emit) async {
    switch (event) {
      case TogglePlayPause():
        final s = state;
        switch (s) {
          case PbActive(playing: true):
            await _transport.pause(); // pause in place
            if (!emit.isDone) emit(PbActive(index: s.index, track: s.track, playing: false));
          case PbActive(playing: false):
            await _transport.play(); // resume WITHOUT reload (keep position)
            if (!emit.isDone) emit(PbActive(index: s.index, track: s.track, playing: true));
          case PbLoading():
            // Toggling mid-load: re-drive the same index with flipped intent.
            await _drive(emit, s.index, intentPlay: !s.intentPlay, direction: 1, userTap: false);
          case PbStopped():
            // Queue ended / idle → (re)load and play the current/last index.
            await _drive(emit, s.index ?? 0, intentPlay: true, direction: 1, userTap: false);
        }
      case SetIntent():
        final s = state;
        if (event.play) {
          switch (s) {
            case PbActive(playing: true):
              break;
            case PbActive(playing: false):
              await _transport.play();
              if (!emit.isDone) emit(PbActive(index: s.index, track: s.track, playing: true));
            case PbLoading():
              await _drive(emit, s.index, intentPlay: true, direction: 1, userTap: false);
            case PbStopped():
              await _drive(emit, s.index ?? 0, intentPlay: true, direction: 1, userTap: false);
          }
        } else {
          // An explicit pause cancels any interruption auto-resume.
          _pausedByInterruption = false;
          switch (s) {
            case PbActive(playing: true):
              await _transport.pause();
              if (!emit.isDone) emit(PbActive(index: s.index, track: s.track, playing: false));
            case PbLoading(intentPlay: true):
              await _drive(emit, s.index, intentPlay: false, direction: 1, userTap: false);
            default:
              break;
          }
        }
      case PlayOneShot():
        _oneShotResume = _playlist.currentOrderIndexNotifier.value;
        _oneShotTrack = event.track;
        _oneShotRepeat = event.repeatOne;
        await _driveOneShot(emit, event.track, intentPlay: true);
      case GoNext():
        if (isOneShot) {
          await _exitOneShotStep(emit, 1); // explicit next exits to the queue
          break;
        }
        final n = _playlist.nextOrderIndex();
        if (n != null) {
          // Commit the index now so a rapid chain of nexts advances per tap
          // (each cancels the prior load but the index has already moved).
          await _playlist.setCurrentOrderIndex(n);
          await _drive(emit, n, intentPlay: true, direction: 1, userTap: false, defer: true);
        }
      case GoPrevious():
        if (isOneShot) {
          await _exitOneShotStep(emit, -1);
          break;
        }
        await _onPrevious(emit);
      case GoToIndex():
        _oneShotTrack = null; // a direct queue selection exits one-shot
        _oneShotResume = null;
        if (event.respectPauseIntent && !event.intentPlay) {
          // setQueue honoring a standing pause: show the index, don't play.
          await _playlist.setCurrentOrderIndex(event.index);
          final t = _playlist.trackForOrderIndex(event.index);
          if (!emit.isDone && t != null) {
            emit(PbActive(index: event.index, track: t, playing: false));
          }
          return;
        }
        await _drive(emit, event.index,
            intentPlay: event.intentPlay,
            direction: event.direction,
            userTap: event.userTap);
      case SeekTo():
        await _transport.seek(event.position);
    }
  }

  // Resolve a playable track from [start] in [direction] (skipping failed), load
  // it (transient-retry / definitive-skip), then play or pause per [intentPlay].
  // `emit.isDone` (set when a newer command supersedes this one) short-circuits
  // every step, so stale work neither emits nor touches the transport.
  Future<void> _drive(Emitter<PbState> emit, int start,
      {required bool intentPlay,
      required int direction,
      required bool userTap,
      bool defer = false}) async {
    if (_playlist.length == 0) {
      if (!emit.isDone) emit(const PbStopped());
      return;
    }
    final step = direction == 0 ? 1 : direction.sign;
    var idx = start;
    for (var attempts = 0; attempts < _playlist.length; attempts++) {
      if (emit.isDone) return;
      if (idx < 0 || idx >= _playlist.length) break;
      final track = _playlist.trackForOrderIndex(idx);
      if (track == null) break;

      if (_failedPaths.contains(track.path) && !(userTap && idx == start)) {
        idx += step;
        continue;
      }

      // Commit the index now (before the heavy load) so the hero advances and a
      // duplicate ended sees PbLoading (B-036). A genuinely missing/unreadable
      // track is detected by the transport load failing — no separate
      // File.exists() preflight (it false-negatives on Android scoped storage,
      // where the playable source is a content URI, not the raw path).
      if (_playlist.currentOrderIndexNotifier.value != idx) {
        await _playlist.setCurrentOrderIndex(idx);
        if (emit.isDone) return;
      }
      emit(PbLoading(index: idx, track: track, intentPlay: intentPlay));
      if (defer && attempts == 0) {
        // For rapid user nav (next/prev), wait out a settle window BEFORE the
        // heavy load. restartable() cancels this handler the moment another tap
        // arrives, so the load (which stops the current track) never fires mid-
        // burst — the current song keeps playing while names cycle at 60fps, and
        // only the track you land on loads. Tap/auto-advance (defer:false) loads
        // immediately so index⟺loaded stays tight.
        await Future<void>.delayed(navSettleDelay);
        if (emit.isDone) return;
      }
      _log('StartLoad: path=${track.path}');
      try {
        await _transport.load(track.path, title: track.title, artist: track.artist);
      } catch (e) {
        if (emit.isDone) return;
        final advance = await _recoverFromLoadError(track, e);
        if (advance == null) {
          if (!emit.isDone) emit(PbStopped(index: idx));
          return;
        }
        idx += step * advance; // 0 = retry same index, 1 = move on
        continue;
      }
      if (emit.isDone) return;
      _failedPaths.remove(track.path);
      if (intentPlay && !_pausedByInterruption) {
        await _transport.play();
      } else {
        await _transport.pause();
      }
      if (emit.isDone) return;
      emit(PbActive(index: idx, track: track, playing: intentPlay && !_pausedByInterruption));
      _preloadNext();
      return;
    }
    if (!emit.isDone) emit(PbStopped(index: start));
  }

  // null = give up (transient threshold). 0 = retry same index. 1 = skip past.
  Future<int?> _recoverFromLoadError(AudioTrack track, Object e) async {
    lastError = (
      path: track.path,
      reason: isTransientLoadError(e) ? 'transport_load_transient' : 'transport_load_error',
      message: e.toString(),
    );
    if (isTransientLoadError(e)) {
      final now = DateTime.now();
      if (_transientWindowStart == null ||
          now.difference(_transientWindowStart!).inSeconds > 5) {
        _transientWindowStart = now;
        _transientCount = 0;
      }
      _transientCount += 1;
      if (_transientCount >= 3) return null;
      await Future<void>.delayed(transientRetryDelay);
      return 0; // retry same index
    }
    _failedPaths.add(track.path);
    debugPrint('Error playing track: $e');
    return 1; // skip past
  }

  // Load+play [track] as a one-shot (outside the queue). The state index mirrors
  // the resume slot so the queue stays put visually; isOneShot stays true so the
  // ended/nav branches know to resume. On definitive failure: clear + stop.
  Future<void> _driveOneShot(Emitter<PbState> emit, AudioTrack track,
      {required bool intentPlay}) async {
    final idx = _oneShotResume ?? 0;
    emit(PbLoading(index: idx, track: track, intentPlay: intentPlay));
    try {
      await _transport.load(track.path, title: track.title, artist: track.artist);
    } catch (e) {
      if (emit.isDone) return;
      if (!isTransientLoadError(e)) _failedPaths.add(track.path);
      _oneShotTrack = null;
      _oneShotResume = null;
      emit(PbStopped(index: idx));
      return;
    }
    if (emit.isDone) return;
    final play = intentPlay && !_pausedByInterruption;
    await (play ? _transport.play() : _transport.pause());
    if (emit.isDone) return;
    emit(PbActive(index: idx, track: track, playing: play));
  }

  // Leave one-shot and step into the queue from the captured resume slot.
  Future<void> _exitOneShotStep(Emitter<PbState> emit, int dir) async {
    final r = _oneShotResume;
    _oneShotTrack = null;
    _oneShotResume = null;
    if (_playlist.length == 0 || r == null) {
      if (!emit.isDone) emit(const PbStopped());
      return;
    }
    final target = (r + dir).clamp(0, _playlist.length - 1).toInt();
    await _drive(emit, target, intentPlay: true, direction: dir, userTap: false);
  }

  Future<void> _onPrevious(Emitter<PbState> emit) async {
    final cur = _playlist.currentOrderIndexNotifier.value;
    if (cur == null) {
      final p = _playlist.previousOrderIndex();
      if (p != null) await _drive(emit, p, intentPlay: true, direction: -1, userTap: false);
      return;
    }
    final isTail = cur == _playlist.length - 1;
    Duration position;
    try {
      position = await _transport.position;
    } catch (_) {
      position = Duration.zero;
    }
    if (emit.isDone) return;
    // Ended tail (stopped / at 0) or >3s in → restart the current track; else
    // step back to the previous (head → restart).
    final endedTail = isTail && (!state.isPlaying || position == Duration.zero);
    if (endedTail || position > const Duration(seconds: 3)) {
      await _restartCurrent(emit, cur);
      return;
    }
    final p = _playlist.previousOrderIndex();
    if (p == null) {
      await _restartCurrent(emit, cur);
      return;
    }
    await _drive(emit, p, intentPlay: true, direction: -1, userTap: false, defer: true);
  }

  // Restart [idx] from 0: reload (robust against a consumed/ended source),
  // seek to zero, and play. Matches the legacy previous()-restart behavior.
  Future<void> _restartCurrent(Emitter<PbState> emit, int idx) async {
    final t = _playlist.trackForOrderIndex(idx);
    if (t == null) return;
    emit(PbLoading(index: idx, track: t, intentPlay: true));
    try {
      await _transport.load(t.path, title: t.title, artist: t.artist);
    } catch (_) {
      if (!emit.isDone) emit(PbStopped(index: idx));
      return;
    }
    if (emit.isDone) return;
    await _transport.seek(Duration.zero);
    await _transport.play();
    if (emit.isDone) return;
    emit(PbActive(index: idx, track: t, playing: true));
  }

  // ---- transport / system events (sequential) ------------------------------

  Future<void> _onEnded(TrackEnded event, Emitter<PbState> emit) async {
    // B-036: an advance is already in flight (we're loading the next track) →
    // ignore a duplicate/stale ended so we don't double-advance.
    if (state is PbLoading) return;
    // Only auto-advance if we were actually playing — a stale ended while
    // paused must not advance the queue.
    if (state is PbActive && !(state as PbActive).playing) return;
    if (isOneShot) {
      if (_oneShotRepeat) {
        await _driveOneShot(emit, _oneShotTrack!, intentPlay: true);
        return;
      }
      final r = _oneShotResume;
      _oneShotTrack = null;
      _oneShotResume = null;
      if (r == null || r + 1 >= _playlist.length) {
        emit(PbStopped(index: r));
        return;
      }
      add(GoToIndex(r + 1, direction: 1)); // resume the queue after the one-shot
      return;
    }
    final n = _playlist.nextOrderIndex();
    if (n == null) {
      emit(PbStopped(index: _playlist.currentOrderIndexNotifier.value));
      return;
    }
    add(GoToIndex(n, direction: 1)); // auto-advance via the restartable path
  }

  Future<void> _onInterruptionBegan(InterruptionBegan event, Emitter<PbState> emit) async {
    if (event.type == AudioInterruptionType.duck) return; // OS attenuates
    final s = state;
    if (s.isPlaying) {
      _pausedByInterruption = true;
      await _transport.pause();
      if (s is PbActive) emit(PbActive(index: s.index, track: s.track, playing: false));
    }
  }

  Future<void> _onInterruptionEnded(InterruptionEnded event, Emitter<PbState> emit) async {
    if (event.type == AudioInterruptionType.duck) return;
    final resume = event.type == AudioInterruptionType.pause && _pausedByInterruption;
    _pausedByInterruption = false;
    final s = state;
    if (resume && s is PbActive) {
      await _transport.play();
      emit(PbActive(index: s.index, track: s.track, playing: true));
    }
  }

  Future<void> _onNoisy(BecameNoisy event, Emitter<PbState> emit) async {
    _pausedByInterruption = false;
    final s = state;
    if (s.isPlaying) {
      await _transport.pause();
      if (s is PbActive) emit(PbActive(index: s.index, track: s.track, playing: false));
    }
  }

  Future<void> _onAdopt(AdoptCurrent event, Emitter<PbState> emit) async {
    final t = _playlist.trackForOrderIndex(event.index);
    if (t != null) {
      emit(PbActive(index: event.index, track: t, playing: event.playing));
    }
  }

  // ---- helpers -------------------------------------------------------------

  void _preloadNext() {
    final n = _playlist.nextOrderIndex();
    if (n == null) return;
    final t = _playlist.trackForOrderIndex(n);
    if (t == null || _failedPaths.contains(t.path)) return;
    unawaited(_transport.preload(t.path));
  }
}
