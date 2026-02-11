import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';

import '../models/audio_track.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/nothing_audio_handler.dart';
import '../services/audio_transport.dart';
import '../services/just_audio_transport.dart';
import '../services/playback_controller.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../services/soloud_spectrum_bridge.dart';
import '../services/soloud_transport.dart';

/// Provider wrapper for PlaybackController.
/// Exposes reactive state via ChangeNotifier for use with Provider.
class AudioPlayerProvider extends ChangeNotifier {
  PlaybackController? _controller;
  AudioTransport? _transport;
  NothingAudioHandler? _androidHandler;
  final PlatformChannels _platformChannels = PlatformChannels();
  final bool? _isAndroidOverride;

  // Android-only: spectrum capture is driven by sessionId from AudioHandler.
  int? _androidSessionId;
  bool _captureEnabled = true;
  SpectrumSettings _settings = const SpectrumSettings();
  StreamSubscription<dynamic>? _androidCustomEventSub;
  StreamSubscription<List<MediaItem>>? _androidQueueSub;
  StreamSubscription<MediaItem?>? _androidMediaItemSub;
  StreamSubscription<PlaybackState>? _androidPlaybackStateSub;

  // Android + SoLoud: bridge for SoLoud FFT data (bypasses native Visualizer).
  SoloudSpectrumBridge? _soloudSpectrumBridge;
  bool _isSoloudActive = false;

  // Reactive state
  SongInfo? _songInfo;
  bool _isPlaying = false;
  List<AudioTrack> _queue = [];
  int? _currentIndex;
  bool _shuffle = false;
  List<double> _spectrumData = List.filled(32, 0.0);

  // Stream subscriptions
  StreamSubscription<List<double>>? _spectrumSubscription;
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();

  // Getters
  SongInfo? get songInfo => _songInfo;
  bool get isPlaying => _isPlaying;
  List<AudioTrack> get queue => _queue;
  int? get currentIndex => _currentIndex;
  bool get shuffle => _shuffle;
  List<double> get spectrumData => _spectrumData;
  Stream<List<double>> get spectrumStream =>
      _transport?.spectrumStream ?? _spectrumController.stream;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;

  // Pass-through to controller
  static Set<String> get supportedExtensions {
    if (Platform.isMacOS) {
      return SoLoudTransport.supportedExtensions;
    } else {
      return JustAudioTransport.supportedExtensions;
    }
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

      // Pull the current sessionId eagerly (customEvent is not replayed).
      // Allow `0` as well (output mix) as a fallback on some devices.
      final initialSessionId = handler.androidAudioSessionId;
      _androidSessionId = (initialSessionId != null && initialSessionId >= 0)
          ? initialSessionId
          : null;
      await _platformChannels.setEqualizerSessionId(_androidSessionId);
      await _platformChannels.updateEqualizerSettings(
        SettingsService().eqSettingsNotifier.value,
      );

      // Eagerly detect SoLoud backend (BehaviorSubject replay is async and
      // may arrive after _captureEnabled is set to false).
      _isSoloudActive = handler.isSoloudBackend;
      if (_isSoloudActive) {
        _soloudSpectrumBridge = SoloudSpectrumBridge(
          sourceStream: handler.spectrumStream,
        );
        _soloudSpectrumBridge!.updateSettings(_settings);
      }

      _androidCustomEventSub = handler.customEventStream.listen((event) {
        if (event is Map && event['type'] == 'sessionId') {
          final raw = (event['value'] as num?)?.toInt();
          // Allow `0` as a fallback (output mix) on devices where app session id
          // isn't available or is delayed.
          _androidSessionId = (raw != null && raw >= 0) ? raw : null;
          _platformChannels.setEqualizerSessionId(_androidSessionId);
          _maybeStartAndroidSpectrum();
        } else if (event is Map && event['type'] == 'backend') {
          _isSoloudActive = event['value'] == 'soloud';
          if (_isSoloudActive && _soloudSpectrumBridge == null) {
            _soloudSpectrumBridge = SoloudSpectrumBridge(
              sourceStream: handler.spectrumStream,
            );
            _soloudSpectrumBridge!.updateSettings(_settings);
          }
          _maybeStartAndroidSpectrum();
        }
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

      _songInfo = controller.songInfoNotifier.value;
      _isPlaying = controller.isPlayingNotifier.value;
      _queue = controller.queueNotifier.value;
      _currentIndex = controller.currentIndexNotifier.value;
      _shuffle = controller.shuffleNotifier.value;

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
      }
    }

    _spectrumSubscription?.cancel();
    _androidCustomEventSub?.cancel();
    _androidQueueSub?.cancel();
    _androidMediaItemSub?.cancel();
    _androidPlaybackStateSub?.cancel();
    _soloudSpectrumBridge?.dispose();
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
      await _androidHandler!.skipToPrevious();
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

  Future<void> shuffleQueue() => _isAndroid
      ? _androidHandler!.customAction('shuffleQueue')
      : _controller!.shuffleQueue();
  Future<void> disableShuffle() => _isAndroid
      ? _androidHandler!.customAction('disableShuffle')
      : _controller!.disableShuffle();

  void setCaptureEnabled(bool enabled) {
    if (_isAndroid) {
      _captureEnabled = enabled;
      if (!enabled) {
        _spectrumSubscription?.cancel();
        _spectrumSubscription = null;
        if (_isSoloudActive) {
          _soloudSpectrumBridge?.stop();
          _androidHandler?.setCaptureEnabled(false);
        }
        _spectrumData = List.filled(32, 0.0);
        notifyListeners();
      } else {
        if (_isSoloudActive) {
          _androidHandler?.setCaptureEnabled(true);
        }
        _maybeStartAndroidSpectrum();
      }
      return;
    }
    _transport?.setCaptureEnabled(enabled);
  }

  void updateSpectrumSettings(SpectrumSettings settings) {
    _settings = settings;
    if (_isAndroid) {
      _soloudSpectrumBridge?.updateSettings(settings);
      if (_isSoloudActive) {
        _androidHandler?.updateSpectrumSettings(settings);
      }
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
    if (_settings.audioSource != AudioSourceMode.player) return;

    // SoLoud path: use the SoLoud FFT bridge instead of native Visualizer.
    if (_isSoloudActive && _soloudSpectrumBridge != null) {
      _spectrumSubscription?.cancel();
      _soloudSpectrumBridge!.start();
      _spectrumSubscription = _soloudSpectrumBridge!.stream.listen((data) {
        _spectrumData = data;
        _spectrumController.add(data);
        notifyListeners();
      });
      return;
    }

    // just_audio path: use native Visualizer via platform channel.
    final sessionId = _androidSessionId;
    if (sessionId == null) return;

    _spectrumSubscription?.cancel();
    _spectrumSubscription = _platformChannels
        .spectrumStream(sessionId: sessionId)
        .listen((data) {
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
    } else if (Platform.isMacOS) {
      _transport = SoLoudTransport();
      _controller = PlaybackController(transport: _transport!);
    } else {
      _transport = JustAudioTransport();
      _controller = PlaybackController(transport: _transport!);
    }
  }
}
