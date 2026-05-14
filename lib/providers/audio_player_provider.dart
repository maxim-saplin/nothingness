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

/// Provider wrapper for PlaybackController.
/// Exposes reactive state via ChangeNotifier for use with Provider.
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

  // Reactive state
  SongInfo? _songInfo;
  bool _isPlaying = false;
  List<AudioTrack> _queue = [];
  int? _currentIndex;
  bool _shuffle = false;
  bool _isOneShot = false;
  List<double> _spectrumData = List.filled(32, 0.0);

  // Stream subscriptions
  StreamSubscription<List<double>>? _spectrumSubscription;
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();

  VoidCallback? _oneShotListener;

  // Getters
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

  // Pass-through to controller
  static Set<String> get supportedExtensions {
    return SoLoudTransport.supportedExtensions;
  }

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Initialize the audio player service and set up listeners.
  Future<void> init() async {
    if (_initialized) return;

    if (_isAndroid) {
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

      // Android spectrum: start disabled until UI requests it via setCaptureEnabled.
      _captureEnabled = false;
    } else {
      final controller = _controller!;
      final transport = _transport!;

      await controller.init();

      controller.songInfoNotifier.addListener(_onSongInfoChanged);
      controller.isPlayingNotifier.addListener(_onIsPlayingChanged);
      controller.queueNotifier.addListener(_onQueueChanged);
      controller.currentIndexNotifier.addListener(_onCurrentIndexChanged);
      controller.shuffleNotifier.addListener(_onShuffleChanged);

      // Mirror the controller's one-shot flag so the UI marker stays in sync
      // when the controller naturally clears the flag (natural end / abort).
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

    _initialized = true;
    notifyListeners();
  }

  @override
  void dispose() {
    if (!_isAndroid) {
      final controller = _controller;
      if (controller != null) {
        controller.songInfoNotifier.removeListener(_onSongInfoChanged);
        controller.isPlayingNotifier.removeListener(_onIsPlayingChanged);
        controller.queueNotifier.removeListener(_onQueueChanged);
        controller.currentIndexNotifier.removeListener(_onCurrentIndexChanged);
        controller.shuffleNotifier.removeListener(_onShuffleChanged);
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

  void _onSongInfoChanged() {
    _songInfo = _controller!.songInfoNotifier.value;
    notifyListeners();
  }

  void _onIsPlayingChanged() {
    _isPlaying = _controller!.isPlayingNotifier.value;
    notifyListeners();
  }

  void _onQueueChanged() {
    _queue = _controller!.queueNotifier.value;
    notifyListeners();
  }

  void _onCurrentIndexChanged() {
    _currentIndex = _controller!.currentIndexNotifier.value;
    notifyListeners();
  }

  void _onShuffleChanged() {
    _shuffle = _controller!.shuffleNotifier.value;
    notifyListeners();
  }

  Future<void> playPause() async {
    if (_isAndroid) {
      final handler = _androidHandler!;
      if (_isPlaying) {
        await handler.pause();
      } else {
        await handler.play();
      }
      return;
    }
    await _controller!.playPause();
  }

  Future<void> next() async {
    if (_isAndroid) {
      await _androidHandler!.skipToNext();
      return;
    }
    await _controller!.next();
  }

  Future<void> previous() async {
    if (_isAndroid) {
      await _androidHandler!.customAction('previous');
      return;
    }
    await _controller!.previous();
  }

  Future<void> seek(Duration position) async {
    if (_isAndroid) {
      await _androidHandler!.seek(position);
      return;
    }
    await _controller!.seek(position);
  }

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    if (_isAndroid) {
      final handler = _androidHandler!;
      await handler.customAction('setQueue', <String, Object?>{
        'tracks': tracks.map(_encodeTrack).toList(growable: false),
        'startIndex': startIndex,
        'shuffle': shuffle,
      });
      return;
    }
    await _controller!.setQueue(
      tracks,
      startIndex: startIndex,
      shuffle: shuffle,
    );
  }

  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false}) =>
      _isAndroid
      ? _androidHandler!.customAction('addTracks', <String, Object?>{
          'tracks': tracks.map(_encodeTrack).toList(growable: false),
          'play': play,
        })
      : _controller!.addTracks(tracks, play: play);

  Future<void> playFromQueueIndex(int orderIndex) => _isAndroid
      ? _androidHandler!.customAction('playFromQueueIndex', orderIndex)
      : _controller!.playFromQueueIndex(orderIndex);

  /// Play [track] as a one-shot — preserves the current queue and resumes at
  /// `queueIndex + 1` on natural end (unless [repeatOne] is true, in which
  /// case the one-shot loops in place).
  ///
  /// Pass-through to [PlaybackController.playOneShot]. The UI marker
  /// [isOneShot] flips immediately and clears via the controller's
  /// [PlaybackController.isOneShotNotifier] when the one-shot ends.
  Future<void> playOneShot(AudioTrack track, {bool repeatOne = false}) async {
    if (_isAndroid) {
      // One-shot on Android is not wired through the AudioHandler yet; this
      // path is reserved for the P3 background-mode integration. Until then,
      // fall back to a plain queue replacement so the UI still works in tests.
      // The Android handler has no `isOneShotNotifier` to mirror, so leave
      // `_isOneShot` false to avoid a stuck marker.
      await setQueue(<AudioTrack>[track], startIndex: 0);
      return;
    }
    // Optimistic flip — the controller will also set its notifier, and our
    // listener mirrors it back. This makes the UI marker reflect immediately.
    _isOneShot = true;
    notifyListeners();
    await _controller!.playOneShot(track, repeatOne: repeatOne);
  }

  Future<void> shuffleQueue() => _isAndroid
      ? _androidHandler!.customAction('shuffleQueue')
      : _controller!.shuffleQueue();
  Future<void> disableShuffle() => _isAndroid
      ? _androidHandler!.customAction('disableShuffle')
      : _controller!.disableShuffle();

  /// Suspend periodic timers to save battery while the app is backgrounded.
  void suspendTimers() {
    if (_isAndroid) {
      // On Android, the audio handler remains responsible for background
      // playback. Suspending the transport here deactivates the audio session
      // and freezes position/session updates right when remote media controls
      // are expected to wake playback back up.
      return;
    } else {
      _controller?.suspendTimers();
    }
  }

  /// Resume periodic timers when returning to foreground.
  void resumeTimers() {
    if (_isAndroid) {
      // See suspendTimers(): Android background playback should not depend on
      // the UI resuming before transport/session bookkeeping is restored.
      return;
    } else {
      _controller?.resumeTimers();
    }
  }

  void setCaptureEnabled(bool enabled) {
    if (_isAndroid) {
      _captureEnabled = enabled;
      if (!enabled) {
        _spectrumSubscription?.cancel();
        _spectrumSubscription = null;
        _androidHandler?.setCaptureEnabled(false);
        _spectrumData = List.filled(32, 0.0);
        notifyListeners();
      } else {
        _androidHandler?.setCaptureEnabled(true);
        _maybeStartAndroidSpectrum();
      }
      return;
    }
    _transport?.setCaptureEnabled(enabled);
  }

  void updateSpectrumSettings(SpectrumSettings settings) {
    if (_isAndroid) {
      _androidHandler?.updateSpectrumSettings(settings);
      _platformChannels.updateSpectrumSettings(settings);
      if (_captureEnabled) {
        _maybeStartAndroidSpectrum();
      }
      return;
    }
    _transport?.updateSpectrumSettings(settings);
  }

  Future<List<AudioTrack>> scanFolder(String rootPath) =>
      _controller?.scanFolder(rootPath) ?? Future.value(const <AudioTrack>[]);
  Future<int> playlistSizeBytes() =>
      _controller?.playlistSizeBytes() ?? Future.value(0);

  /// Diagnostics snapshot of the playback controller (audio events, queue,
  /// recent logs). Returns null if no controller is reachable from this
  /// provider (very early init).
  Map<String, Object?>? diagnosticsSnapshot() {
    if (_isAndroid) return _androidHandler?.diagnosticsSnapshot();
    return _controller?.diagnosticsSnapshot();
  }

  /// Audio-event ring buffer for diagnosing interruption / route issues.
  List<String> audioEvents() {
    if (_isAndroid) return _androidHandler?.audioEvents() ?? const <String>[];
    return _controller?.audioEvents() ?? const <String>[];
  }

  /// Test seam: simulate an audio interruption event in the controller.
  void debugSimulateInterruption(AudioInterruptionEvent event) {
    if (_isAndroid) {
      _androidHandler?.debugSimulateInterruption(event);
    } else {
      _controller?.debugSimulateInterruption(event);
    }
  }

  /// Test seam: simulate an audio-becoming-noisy event in the controller.
  void debugSimulateBecomingNoisy() {
    if (_isAndroid) {
      _androidHandler?.debugSimulateBecomingNoisy();
    } else {
      _controller?.debugSimulateBecomingNoisy();
    }
  }

  Map<String, Object?> _encodeTrack(AudioTrack t) {
    return <String, Object?>{
      'path': t.path,
      'title': t.title,
      'artist': t.artist,
      'durationMs': t.duration?.inMilliseconds,
    };
  }

  void _syncSongInfoFromHandler() {
    final handler = _androidHandler;
    if (handler == null) return;
    final m = handler.mediaItem.value;
    final s = handler.playbackState.value;
    if (m == null) {
      _songInfo = null;
      return;
    }
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

  /// Test-only constructor that forces the PlaybackController path on Android.
  ///
  /// This intentionally bypasses AudioService/AudioHandler and is intended for
  /// deterministic emulator integration tests (no real audio files).
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
