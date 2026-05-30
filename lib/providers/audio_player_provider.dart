import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/nothing_audio_handler.dart';
import '../services/audio_transport.dart';
import '../services/playback_controller.dart';
import '../services/platform_channels.dart';
import '../services/soloud_transport.dart';

/// ChangeNotifier wrapper exposing PlaybackController reactive state to the UI.
class AudioPlayerProvider extends ChangeNotifier {
  PlaybackController? _controller;
  AudioTransport? _transport;
  NothingAudioHandler? _androidHandler;
  final PlatformChannels _platformChannels = PlatformChannels();
  final bool? _isAndroidOverride;

  bool _captureEnabled = true;
  StreamSubscription<List<MediaItem>>? _androidQueueSub;
  StreamSubscription<MediaItem?>? _androidMediaItemSub;
  StreamSubscription<PlaybackState>? _androidPlaybackStateSub;

  // Reactive state.
  SongInfo? _songInfo;
  bool _isPlaying = false;
  List<AudioTrack> _queue = [];
  int? _currentIndex;
  bool _shuffle = false;
  bool _isOneShot = false;
  List<double> _spectrumData = List.filled(32, 0.0);

  StreamSubscription<List<double>>? _spectrumSubscription;
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();

  VoidCallback? _oneShotListener;

  SongInfo? get songInfo => _songInfo;
  bool get isPlaying => _isPlaying;
  List<AudioTrack> get queue => _queue;
  int? get currentIndex => _currentIndex;
  bool get shuffle => _shuffle;
  bool get isOneShot => _isOneShot;
  List<double> get spectrumData => _spectrumData;
  Stream<List<double>> get spectrumStream =>
      _transport?.spectrumStream ?? _spectrumController.stream;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;

  static Set<String> get supportedExtensions =>
      SoLoudTransport.supportedExtensions;

  bool _initialized = false;
  bool get initialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _isAndroid ? await _initAndroid() : await _initController();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _initAndroid() async {
    final handler = _androidHandler;
    if (handler == null) {
      throw StateError(
        'AudioPlayerProvider(android): androidHandler is required on Android',
      );
    }
    await handler.ready;

    // Mirror handler streams into provider state.
    _androidQueueSub = handler.queue.listen((items) {
      _queue = items
          .map(
            (m) => AudioTrack(
              path: m.id,
              title: m.title,
              artist: m.artist ?? '',
              duration: m.duration,
              isNotFound: (m.extras?['isNotFound'] as bool?) ?? false,
            ),
          )
          .toList(growable: false);
      _syncSongInfoFromHandler();
      notifyListeners();
    });

    _androidMediaItemSub = handler.mediaItem.listen((m) {
      _syncSongInfoFromHandler();
      notifyListeners();
    });

    _androidPlaybackStateSub = handler.playbackState.listen((s) {
      _isPlaying = s.playing;
      _currentIndex = s.queueIndex;
      _shuffle = s.shuffleMode == AudioServiceShuffleMode.all;
      _syncSongInfoFromHandler();
      notifyListeners();
    });

    // Android spectrum stays off until the UI requests it.
    _captureEnabled = false;
  }

  Future<void> _initController() async {
    final controller = _controller!;
    final transport = _transport!;

    await controller.init();

    controller.songInfoNotifier.addListener(_onControllerChanged);
    controller.isPlayingNotifier.addListener(_onControllerChanged);
    controller.queueNotifier.addListener(_onControllerChanged);
    controller.currentIndexNotifier.addListener(_onControllerChanged);
    controller.shuffleNotifier.addListener(_onControllerChanged);

    // Mirror the controller's one-shot flag so the UI marker stays in sync
    // when the controller clears it (natural end / abort).
    _oneShotListener = () {
      _isOneShot = controller.isOneShotNotifier.value;
      notifyListeners();
    };
    controller.isOneShotNotifier.addListener(_oneShotListener!);

    _songInfo = controller.songInfoNotifier.value;
    _isPlaying = controller.isPlayingNotifier.value;
    _queue = controller.queueNotifier.value;
    _currentIndex = controller.currentIndexNotifier.value;
    _shuffle = controller.shuffleNotifier.value;
    _isOneShot = controller.isOneShotNotifier.value;

    _spectrumSubscription = transport.spectrumStream.listen((data) {
      _spectrumData = data;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    if (!_isAndroid) {
      final controller = _controller;
      if (controller != null) {
        controller.songInfoNotifier.removeListener(_onControllerChanged);
        controller.isPlayingNotifier.removeListener(_onControllerChanged);
        controller.queueNotifier.removeListener(_onControllerChanged);
        controller.currentIndexNotifier.removeListener(_onControllerChanged);
        controller.shuffleNotifier.removeListener(_onControllerChanged);
        final oneShotListener = _oneShotListener;
        if (oneShotListener != null) {
          controller.isOneShotNotifier.removeListener(oneShotListener);
        }
      }
    }

    _spectrumSubscription?.cancel();
    _androidQueueSub?.cancel();
    _androidMediaItemSub?.cancel();
    _androidPlaybackStateSub?.cancel();
    _spectrumController.close();
    _controller?.dispose();
    super.dispose();
  }

  /// Single listener registered on every controller notifier: re-mirror all
  /// fields and notify.
  void _onControllerChanged() {
    final controller = _controller!;
    _songInfo = controller.songInfoNotifier.value;
    _isPlaying = controller.isPlayingNotifier.value;
    _queue = controller.queueNotifier.value;
    _currentIndex = controller.currentIndexNotifier.value;
    _shuffle = controller.shuffleNotifier.value;
    notifyListeners();
  }

  Future<void> playPause() async {
    if (_isAndroid) {
      final handler = _androidHandler!;
      _isPlaying ? await handler.pause() : await handler.play();
      return;
    }
    await _controller!.playPause();
  }

  /// Dispatch a 1:1 call to the Android handler or the controller.
  Future<T> _delegate<T>(
    Future<T> Function(NothingAudioHandler h) android,
    Future<T> Function(PlaybackController c) controller,
  ) => _isAndroid ? android(_androidHandler!) : controller(_controller!);

  Future<void> next() => _delegate((h) => h.skipToNext(), (c) => c.next());

  Future<void> previous() =>
      _delegate((h) => h.customAction('previous'), (c) => c.previous());

  Future<void> seek(Duration position) =>
      _delegate((h) => h.seek(position), (c) => c.seek(position));

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) => _delegate(
        (h) => h.customAction('setQueue', <String, Object?>{
          'tracks': _encodeTracks(tracks),
          'startIndex': startIndex,
          'shuffle': shuffle,
        }),
        (c) => c.setQueue(tracks, startIndex: startIndex, shuffle: shuffle),
      );

  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false}) =>
      _delegate(
        (h) => h.customAction('addTracks', <String, Object?>{
          'tracks': _encodeTracks(tracks),
          'play': play,
        }),
        (c) => c.addTracks(tracks, play: play),
      );

  Future<void> playFromQueueIndex(int orderIndex) => _delegate(
    (h) => h.customAction('playFromQueueIndex', orderIndex),
    (c) => c.playFromQueueIndex(orderIndex),
  );

  /// Play [track] as a one-shot — see [PlaybackController.playOneShot].
  /// [isOneShot] flips immediately and clears via the controller's notifier.
  Future<void> playOneShot(AudioTrack track, {bool repeatOne = false}) async {
    if (_isAndroid) {
      // One-shot isn't wired through the AudioHandler yet (P3 background-mode);
      // fall back to queue replacement and leave _isOneShot false (no notifier).
      await setQueue(<AudioTrack>[track], startIndex: 0);
      return;
    }
    // Optimistic flip; the listener mirrors the controller's notifier back.
    _isOneShot = true;
    notifyListeners();
    await _controller!.playOneShot(track, repeatOne: repeatOne);
  }

  /// Install [results] as a search-session sub-queue at [tappedIndex]; the
  /// prior queue is restored on [exitSearchSession]. B-014.
  Future<void> enterSearchSession(
    List<AudioTrack> results,
    int tappedIndex,
  ) => _delegate(
        (h) => h.customAction('enterSearchSession', <String, Object?>{
          'tracks': _encodeTracks(results),
          'tappedIndex': tappedIndex,
        }),
        (c) => c.enterSearchSession(results, tappedIndex),
      );

  /// Restore the queue captured at search-session start; the playing track
  /// keeps playing. No-op if no session is active. B-014.
  Future<void> exitSearchSession() => _delegate(
    (h) => h.customAction('exitSearchSession'),
    (c) => c.exitSearchSession(),
  );

  Future<void> shuffleQueue() =>
      _delegate((h) => h.customAction('shuffleQueue'), (c) => c.shuffleQueue());

  Future<void> disableShuffle() => _delegate(
    (h) => h.customAction('disableShuffle'),
    (c) => c.disableShuffle(),
  );

  /// No-op on Android: the handler owns background playback, so suspending the
  /// transport here would freeze session/position updates.
  void suspendTimers() {
    if (_isAndroid) return;
    _controller?.suspendTimers();
  }

  void resumeTimers() {
    if (_isAndroid) return;
    _controller?.resumeTimers();
  }

  void setCaptureEnabled(bool enabled) {
    if (!_isAndroid) {
      _transport?.setCaptureEnabled(enabled);
      return;
    }
    _captureEnabled = enabled;
    if (enabled) {
      _androidHandler?.setCaptureEnabled(true);
      _maybeStartAndroidSpectrum();
    } else {
      _spectrumSubscription?.cancel();
      _spectrumSubscription = null;
      _androidHandler?.setCaptureEnabled(false);
      _spectrumData = List.filled(32, 0.0);
      notifyListeners();
    }
  }

  void updateSpectrumSettings(SpectrumSettings settings) {
    if (!_isAndroid) {
      _transport?.updateSpectrumSettings(settings);
      return;
    }
    _androidHandler?.updateSpectrumSettings(settings);
    _platformChannels.updateSpectrumSettings(settings);
    if (_captureEnabled) _maybeStartAndroidSpectrum();
  }

  Future<List<AudioTrack>> scanFolder(String rootPath) =>
      _controller?.scanFolder(rootPath) ?? Future.value(const <AudioTrack>[]);

  Future<int> playlistSizeBytes() =>
      _controller?.playlistSizeBytes() ?? Future.value(0);

  /// Controller diagnostics; null if no controller is reachable (early init).
  Map<String, Object?>? diagnosticsSnapshot() => _isAndroid
      ? _androidHandler?.diagnosticsSnapshot()
      : _controller?.diagnosticsSnapshot();

  List<String> audioEvents() => _isAndroid
      ? (_androidHandler?.audioEvents() ?? const <String>[])
      : (_controller?.audioEvents() ?? const <String>[]);

  /// Test seam: simulate an audio interruption event.
  void debugSimulateInterruption(AudioInterruptionEvent event) => _isAndroid
      ? _androidHandler?.debugSimulateInterruption(event)
      : _controller?.debugSimulateInterruption(event);

  /// Test seam: simulate an audio-becoming-noisy event.
  void debugSimulateBecomingNoisy() => _isAndroid
      ? _androidHandler?.debugSimulateBecomingNoisy()
      : _controller?.debugSimulateBecomingNoisy();

  Map<String, Object?> _encodeTrack(AudioTrack t) => <String, Object?>{
        'path': t.path,
        'title': t.title,
        'artist': t.artist,
        'durationMs': t.duration?.inMilliseconds,
      };

  List<Map<String, Object?>> _encodeTracks(List<AudioTrack> tracks) =>
      tracks.map(_encodeTrack).toList(growable: false);

  void _syncSongInfoFromHandler() {
    final handler = _androidHandler;
    if (handler == null) return;
    final m = handler.mediaItem.value;
    if (m == null) {
      _songInfo = null;
      return;
    }
    final s = handler.playbackState.value;
    _songInfo = SongInfo(
      track: AudioTrack(
        path: m.id,
        title: m.title,
        artist: m.artist ?? '',
        duration: m.duration,
      ),
      isPlaying: s.playing,
      position: s.updatePosition.inMilliseconds,
      duration: (m.duration ?? Duration.zero).inMilliseconds,
    );
  }

  void _maybeStartAndroidSpectrum() {
    if (!_captureEnabled) return;
    _spectrumSubscription?.cancel();
    _spectrumSubscription = _androidHandler!.spectrumStream.listen((data) {
      _spectrumData = data;
      _spectrumController.add(data);
      notifyListeners();
    });
  }

  /// Test-only: forces the PlaybackController path (bypasses AudioService) for
  /// deterministic emulator integration tests.
  AudioPlayerProvider.forTests({
    required PlaybackController controller,
    required AudioTransport transport,
  }) : _controller = controller,
       _transport = transport,
       _androidHandler = null,
       _isAndroidOverride = false;

  AudioPlayerProvider({
    NothingAudioHandler? androidHandler,
    PlaybackController? controller,
    AudioTransport? transport,
    bool? isAndroidOverride,
  }) : _isAndroidOverride = isAndroidOverride {
    if (controller != null || transport != null) {
      if (controller == null || transport == null) {
        throw ArgumentError(
          'AudioPlayerProvider: controller and transport must be provided together',
        );
      }
      _controller = controller;
      _transport = transport;
      _androidHandler = androidHandler;
      return;
    }

    if (Platform.isAndroid) {
      _androidHandler = androidHandler;
    } else {
      _transport = SoLoudTransport();
      _controller = PlaybackController(transport: _transport!);
    }
  }
}
