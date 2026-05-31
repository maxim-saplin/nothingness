import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';

import '../../models/audio_track.dart';
import '../audio_transport.dart';
import '../playlist_store.dart';

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
    Future<bool> Function(String path)? fileExists,
    this.preflightFileExists = true,
    this.transientRetryDelay = const Duration(milliseconds: 200),
  })  : _transport = transport,
        _playlist = playlist,
        _fileExists = fileExists ?? _defaultFileExists,
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
  final Future<bool> Function(String path) _fileExists;
  final bool preflightFileExists;
  final Duration transientRetryDelay;

  final Set<String> _failedPaths = <String>{};
  bool _pausedByInterruption = false;
  int _transientCount = 0;
  DateTime? _transientWindowStart;

  // Last load failure, surfaced for the controller's diagnostics snapshot.
  ({String path, String reason, String message})? lastError;

  Set<String> get failedPaths => Set.unmodifiable(_failedPaths);

  static Future<bool> _defaultFileExists(String _) async => true;

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
      case GoNext():
        final n = _playlist.nextOrderIndex();
        if (n != null) {
          // Commit the index now so a rapid chain of nexts advances per tap
          // (each cancels the prior load but the index has already moved).
          await _playlist.setCurrentOrderIndex(n);
          await _drive(emit, n, intentPlay: true, direction: 1, userTap: false);
        }
      case GoPrevious():
        await _onPrevious(emit);
      case GoToIndex():
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
      {required bool intentPlay, required int direction, required bool userTap}) async {
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
      if (_shouldPreflight(track.path) && !await _fileExists(track.path)) {
        if (emit.isDone) return;
        lastError = (path: track.path, reason: 'preflight_missing', message: 'File does not exist');
        _failedPaths.add(track.path);
        idx += step;
        continue;
      }

      emit(PbLoading(index: idx, track: track, intentPlay: intentPlay));
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
      await _playlist.setCurrentOrderIndex(idx);
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
      reason: _isTransient(e) ? 'transport_load_transient' : 'transport_load_error',
      message: e.toString(),
    );
    if (_isTransient(e)) {
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

  Future<void> _onPrevious(Emitter<PbState> emit) async {
    final cur = _playlist.currentOrderIndexNotifier.value;
    if (cur == null) {
      final p = _playlist.previousOrderIndex();
      if (p != null) await _drive(emit, p, intentPlay: true, direction: -1, userTap: false);
      return;
    }
    Duration position;
    try {
      position = await _transport.position;
    } catch (_) {
      position = Duration.zero;
    }
    if (emit.isDone) return;
    final atStart = !state.isPlaying || position <= const Duration(seconds: 3);
    if (!atStart) {
      // >3s in → restart current.
      await _drive(emit, cur, intentPlay: true, direction: 1, userTap: false);
      return;
    }
    final p = _playlist.previousOrderIndex();
    await _drive(emit, p ?? cur, intentPlay: true, direction: p != null ? -1 : 1, userTap: false);
  }

  // ---- transport / system events (sequential) ------------------------------

  Future<void> _onEnded(TrackEnded event, Emitter<PbState> emit) async {
    // B-036: an advance is already in flight (we're loading the next track) →
    // ignore a duplicate/stale ended so we don't double-advance.
    if (state is PbLoading) return;
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

  bool _shouldPreflight(String path) {
    if (!preflightFileExists || path.isEmpty) return false;
    final uri = Uri.tryParse(path);
    return !(uri != null && uri.hasScheme);
  }

  bool _isTransient(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('connection aborted') || s.contains('10000000');
  }

  void _preloadNext() {
    final n = _playlist.nextOrderIndex();
    if (n == null) return;
    final t = _playlist.trackForOrderIndex(n);
    if (t == null || _failedPaths.contains(t.path)) return;
    unawaited(_transport.preload(t.path));
  }
}
