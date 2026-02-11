import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';
import '../models/spectrum_settings.dart';
import 'audio_transport.dart';
import 'just_audio_transport.dart';
import 'soloud_transport.dart';
import 'playback_controller.dart';
import 'playlist_store.dart';

/// Android playback entrypoint.
///
/// Owns MediaSession/notification state and bridges it to [PlaybackController],
/// which remains the single source of truth for queue/index/shuffle logic.
class NothingAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  factory NothingAudioHandler({bool debugLogs = false, bool useSoloud = false}) {
    final AudioTransport transport = useSoloud
        ? (SoLoudTransport()..setCaptureEnabled(false))
        : (JustAudioTransport()..setCaptureEnabled(false));
    final controller = PlaybackController(
      transport: transport,
      playlist: PlaylistStore(),
      debugPlaybackLogs: debugLogs,
    );
    return NothingAudioHandler._(controller: controller, transport: transport);
  }

  NothingAudioHandler._({
    required PlaybackController controller,
    required AudioTransport transport,
  })  : _controller = controller,
        _transport = transport {
    unawaited(_init());
  }

  final PlaybackController _controller;
  final AudioTransport _transport;

  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get ready => _initCompleter.future;

  /// Convenience stream for UI layer (provider) to subscribe to custom events.
  ///
  /// In particular, we emit `{type: 'sessionId', value: <int?>}` and
  /// `{type: 'backend', value: 'soloud'|'just_audio'}` updates.
  Stream<dynamic> get customEventStream => customEvent;

  /// Whether this handler was initialised with the SoLoud backend.
  bool get isSoloudBackend => _transport is SoLoudTransport;

  /// Spectrum stream from the transport (useful when SoLoud is active and
  /// the native Visualizer is unavailable).
  Stream<List<double>> get spectrumStream => _transport.spectrumStream;

  /// Enable or disable spectrum capture on the underlying transport.
  void setCaptureEnabled(bool enabled) {
    _transport.setCaptureEnabled(enabled);
  }

  /// Forward spectrum settings to the underlying transport.
  void updateSpectrumSettings(SpectrumSettings settings) {
    _transport.updateSpectrumSettings(settings);
  }

  /// Android-only: exposes the latest known audio session id for the player.
  ///
  /// This is needed because `customEvent` is not replayed; consumers that
  /// subscribe after `ready` would otherwise miss the initial session id.
  int? get androidAudioSessionId {
    if (_transport is JustAudioTransport) {
      return (_transport).androidAudioSessionId;
    }
    return null; // SoLoud path: no platform session id
  }

  StreamSubscription<TransportEvent>? _transportEventsSub;
  StreamSubscription<int?>? _sessionIdSub;

  Duration _lastPosition = Duration.zero;

  VoidCallback? _queueListener;
  VoidCallback? _indexListener;
  VoidCallback? _playingListener;
  VoidCallback? _songInfoListener;
  VoidCallback? _shuffleListener;

  Future<void> _init() async {
    try {
      await _controller.init();

      _queueListener = _updateQueue;
      _indexListener = () {
        _updateMediaItem();
        _updatePlaybackState();
      };
      _playingListener = _updatePlaybackState;
      _songInfoListener = () {
        _updateMediaItem();
        _updatePlaybackState();
      };
      _shuffleListener = _updatePlaybackState;

      _controller.queueNotifier.addListener(_queueListener!);
      _controller.currentIndexNotifier.addListener(_indexListener!);
      _controller.isPlayingNotifier.addListener(_playingListener!);
      _controller.songInfoNotifier.addListener(_songInfoListener!);
      _controller.shuffleNotifier.addListener(_shuffleListener!);

      // Use transport position events to keep playbackState.position updated.
      _transportEventsSub = _transport.eventStream.listen((event) {
        if (event case TransportPositionEvent(position: final position)) {
          _lastPosition = position;
          _updatePlaybackState();
        } else if (event case TransportLoadedEvent()) {
          _updatePlaybackState();
        } else if (event case TransportEndedEvent()) {
          _updatePlaybackState();
        } else if (event case TransportErrorEvent()) {
          _updatePlaybackState();
        }
      });

      // Forward audio session id to the UI for Visualizer-based spectrum.
      if (_transport is JustAudioTransport) {
        _sessionIdSub =
            (_transport).androidAudioSessionIdStream.listen((id) {
          customEvent.add(<String, Object?>{'type': 'sessionId', 'value': id});
        });
        // Also emit the current value so late subscribers don't miss the first id.
        customEvent.add(<String, Object?>{
          'type': 'sessionId',
          'value': (_transport).androidAudioSessionId,
        });
      } else {
        // SoLoud path: emit null so UI can avoid Visualizer-based spectrum
        customEvent.add(<String, Object?>{'type': 'sessionId', 'value': null});
      }

      // Emit backend type so the provider can route spectrum correctly.
      customEvent.add(<String, Object?>{
        'type': 'backend',
        'value': _transport is SoLoudTransport ? 'soloud' : 'just_audio',
      });

      // Initial push.
      _updateQueue();
      _updateMediaItem();
      _updatePlaybackState();

      _initCompleter.complete();
    } catch (e, st) {
      debugPrint('[NothingAudioHandler] init error: $e');
      if (!_initCompleter.isCompleted) {
        _initCompleter.completeError(e, st);
      }
    }
  }

  static MediaItem _toMediaItem(AudioTrack t) {
    return MediaItem(
      id: t.path,
      title: t.title,
      artist: t.artist,
      duration: t.duration,
      extras: <String, Object?>{
        'isNotFound': t.isNotFound,
      },
    );
  }

  void _updateQueue() {
    final items = _controller.queueNotifier.value.map(_toMediaItem).toList();
    queue.add(items);
  }

  void _updateMediaItem() {
    final si = _controller.songInfoNotifier.value;
    if (si == null) {
      mediaItem.add(null);
      return;
    }
    // Important: queue tracks often have unknown duration until loaded.
    // Use the controller's resolved duration so UI seek bars behave correctly.
    mediaItem.add(
      MediaItem(
        id: si.track.path,
        title: si.track.title,
        artist: si.track.artist,
        duration: Duration(milliseconds: si.duration),
      ),
    );
  }

  void _updatePlaybackState() {
    final playing = _controller.isPlayingNotifier.value;
    final currentQueue = queue.value;
    final currentMedia = mediaItem.value;
    final int? idx =
        currentMedia == null ? null : currentQueue.indexWhere((m) => m.id == currentMedia.id);
    final shuffle = _controller.shuffleNotifier.value;

    playbackState.add(
      playbackState.value.copyWith(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const <int>[0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: _lastPosition,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        queueIndex: (idx != null && idx >= 0) ? idx : null,
        shuffleMode: shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
        repeatMode: AudioServiceRepeatMode.none,
      ),
    );
  }

  @override
  Future<void> play() async {
    await ready;
    if (!_controller.isPlayingNotifier.value) {
      await _controller.playPause();
    }
  }

  @override
  Future<void> pause() async {
    await ready;
    if (_controller.isPlayingNotifier.value) {
      await _controller.playPause();
    }
  }

  @override
  Future<void> stop() async {
    await pause();
    await _cleanup();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await ready;
    await _controller.seek(position);
    _lastPosition = position;
    _updatePlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    await ready;
    await _controller.next();
  }

  @override
  Future<void> skipToPrevious() async {
    await ready;
    await _controller.previous();
  }

  @override
  Future<dynamic> customAction(String name, [dynamic extras]) async {
    await ready;

    switch (name) {
      case 'setQueue':
        final map = (extras as Map?) ?? const <String, Object?>{};
        final tracks = _decodeTracks(map['tracks']);
        final startIndex = (map['startIndex'] as num?)?.toInt() ?? 0;
        final shuffle = map['shuffle'] as bool? ?? false;
        await _controller.setQueue(tracks, startIndex: startIndex, shuffle: shuffle);
        return null;
      case 'addTracks':
        final map = (extras as Map?) ?? const <String, Object?>{};
        final tracks = _decodeTracks(map['tracks']);
        final play = map['play'] as bool? ?? false;
        await _controller.addTracks(tracks, play: play);
        return null;
      case 'shuffleQueue':
        await _controller.shuffleQueue();
        return null;
      case 'disableShuffle':
        await _controller.disableShuffle();
        return null;
      case 'playFromQueueIndex':
        final idx = (extras as num?)?.toInt();
        if (idx == null) return null;
        await _controller.playFromQueueIndex(idx);
        return null;
    }

    return super.customAction(name, extras);
  }

  List<AudioTrack> _decodeTracks(dynamic raw) {
    if (raw is! List) return const <AudioTrack>[];
    return raw.whereType<Map>().map((m) {
      final path = m['path'] as String? ?? '';
      if (path.isEmpty) return null;
      final durationMs = m['durationMs'] as int?;
      return AudioTrack(
        path: path,
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? '',
        duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
      );
    }).whereType<AudioTrack>().toList(growable: false);
  }

  Future<void> _cleanup() async {
    if (_queueListener != null) {
      _controller.queueNotifier.removeListener(_queueListener!);
    }
    if (_indexListener != null) {
      _controller.currentIndexNotifier.removeListener(_indexListener!);
    }
    if (_playingListener != null) {
      _controller.isPlayingNotifier.removeListener(_playingListener!);
    }
    if (_songInfoListener != null) {
      _controller.songInfoNotifier.removeListener(_songInfoListener!);
    }
    if (_shuffleListener != null) {
      _controller.shuffleNotifier.removeListener(_shuffleListener!);
    }
    await _transportEventsSub?.cancel();
    await _sessionIdSub?.cancel();
    await _controller.dispose();
  }
}


