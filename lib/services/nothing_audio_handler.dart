import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';
import 'android_audio_source.dart';
import 'audio_transport.dart';
import 'soloud_transport.dart';
import 'playback_controller.dart';
import 'playlist_store.dart';

/// Android playback entrypoint. Owns MediaSession/notification state and
/// bridges it to [PlaybackController] (the source of truth for queue/index).
class NothingAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  factory NothingAudioHandler({bool debugLogs = false}) {
    // Android: load shared-storage tracks via MediaStore content URIs (scoped
    // storage blocks raw-path access on API 30+). B-049 spike: fd-first to keep
    // the whole-file bytes off the UI isolate; readBytes is the fallback.
    final transport = SoLoudTransport(
      openFd: openAndroidAudioFd,
      closeFd: closeAndroidAudioFd,
    )..setCaptureEnabled(false);
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
  }) : _controller = controller,
       _transport = transport {
    unawaited(_init());
  }

  final PlaybackController _controller;
  final AudioTransport _transport;

  /// The single source of truth for playback. The UI watches this directly;
  /// the handler only OBSERVES it to mirror state into the OS MediaSession.
  PlaybackController get controller => _controller;

  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get ready => _initCompleter.future;

  Duration _lastPosition = Duration.zero;

  Future<void> _init() async {
    try {
      await _controller.init();

      void mediaThenState() {
        _updateMediaItem();
        _updatePlaybackState();
      }

      _controller.queueNotifier.addListener(_updateQueue);
      _controller.currentIndexNotifier.addListener(mediaThenState);
      _controller.isPlayingNotifier.addListener(_updatePlaybackState);
      _controller.songInfoNotifier.addListener(mediaThenState);
      _controller.shuffleNotifier.addListener(_updatePlaybackState);

      // Keep playbackState.position updated from transport position events.
      _transport.eventStream.listen((event) {
        if (event case TransportPositionEvent(position: final position)) {
          if ((position - _lastPosition).abs() <
              const Duration(milliseconds: 200)) {
            return;
          }
          _lastPosition = position;
          _updatePlaybackState();
        } else if (event is TransportLoadedEvent ||
            event is TransportEndedEvent ||
            event is TransportErrorEvent) {
          _updatePlaybackState();
        }
      });

      // Initial push.
      _updateQueue();
      _updateMediaItem();
      _updatePlaybackState();

      _initCompleter.complete();
    } catch (e, st) {
      debugPrint('[NothingAudioHandler] init error: $e');
      if (!_initCompleter.isCompleted) _initCompleter.completeError(e, st);
    }
  }

  static MediaItem _toMediaItem(AudioTrack t) => MediaItem(
        id: t.path,
        title: t.title,
        artist: t.artist,
        duration: t.duration,
        extras: <String, Object?>{'isNotFound': t.isNotFound},
      );

  void _updateQueue() {
    queue.add(_controller.queueNotifier.value.map(_toMediaItem).toList());
  }

  void _updateMediaItem() {
    final si = _controller.songInfoNotifier.value;
    if (si == null) {
      mediaItem.add(null);
      return;
    }
    // Use the controller's resolved duration (queue tracks lack it until
    // loaded) so UI seek bars behave correctly.
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
    final currentMedia = mediaItem.value;
    final idx = currentMedia == null
        ? null
        : queue.value.indexWhere((m) => m.id == currentMedia.id);
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
        shuffleMode: shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: AudioServiceRepeatMode.none,
      ),
    );
  }

  @override
  Future<void> play() async {
    await ready;
    if (_controller.isPlayingNotifier.value) return;
    try {
      await _controller.playPause();
    } catch (e) {
      // Some OEM paths invalidate the source while keeping the session alive;
      // force-reload the current queue item if plain play fails.
      debugPrint('[NothingAudioHandler] play() failed, forcing reload: $e');
      await _controller.playFromQueueIndex(
        _controller.currentIndexNotifier.value ?? 0,
      );
    }
  }

  @override
  Future<void> pause() async {
    await ready;
    if (_controller.isPlayingNotifier.value) await _controller.playPause();
  }

  @override
  Future<void> stop() async {
    // Treat as pause: fully disposing leaves a zombie session that won't react
    // to Play without an app restart.
    await pause();
    _updatePlaybackState();
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
}
