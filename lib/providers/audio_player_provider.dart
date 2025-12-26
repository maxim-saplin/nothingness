import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/audio_transport.dart';
import '../services/just_audio_transport.dart';
import '../services/playback_controller.dart';
import '../services/soloud_transport.dart';

/// Provider wrapper for PlaybackController.
/// Exposes reactive state via ChangeNotifier for use with Provider.
class AudioPlayerProvider extends ChangeNotifier {
  late final PlaybackController _controller;
  late final AudioTransport _transport;

  AudioPlayerProvider() {
    if (Platform.isMacOS) {
      _transport = SoLoudTransport();
    } else {
      _transport = JustAudioTransport();
    }
    _controller = PlaybackController(transport: _transport);
  }

  // Reactive state
  SongInfo? _songInfo;
  bool _isPlaying = false;
  List<AudioTrack> _queue = [];
  int? _currentIndex;
  bool _shuffle = false;
  List<double> _spectrumData = List.filled(32, 0.0);

  // Stream subscriptions
  StreamSubscription<List<double>>? _spectrumSubscription;

  // Getters
  SongInfo? get songInfo => _songInfo;
  bool get isPlaying => _isPlaying;
  List<AudioTrack> get queue => _queue;
  int? get currentIndex => _currentIndex;
  bool get shuffle => _shuffle;
  List<double> get spectrumData => _spectrumData;
  Stream<List<double>> get spectrumStream => _transport.spectrumStream;

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

    await _controller.init();

    _controller.songInfoNotifier.addListener(_onSongInfoChanged);
    _controller.isPlayingNotifier.addListener(_onIsPlayingChanged);
    _controller.queueNotifier.addListener(_onQueueChanged);
    _controller.currentIndexNotifier.addListener(_onCurrentIndexChanged);
    _controller.shuffleNotifier.addListener(_onShuffleChanged);

    _songInfo = _controller.songInfoNotifier.value;
    _isPlaying = _controller.isPlayingNotifier.value;
    _queue = _controller.queueNotifier.value;
    _currentIndex = _controller.currentIndexNotifier.value;
    _shuffle = _controller.shuffleNotifier.value;

    _spectrumSubscription = _transport.spectrumStream.listen((data) {
      _spectrumData = data;
      notifyListeners();
    });

    _initialized = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller.songInfoNotifier.removeListener(_onSongInfoChanged);
    _controller.isPlayingNotifier.removeListener(_onIsPlayingChanged);
    _controller.queueNotifier.removeListener(_onQueueChanged);
    _controller.currentIndexNotifier.removeListener(_onCurrentIndexChanged);
    _controller.shuffleNotifier.removeListener(_onShuffleChanged);
    _spectrumSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSongInfoChanged() {
    _songInfo = _controller.songInfoNotifier.value;
    notifyListeners();
  }

  void _onIsPlayingChanged() {
    _isPlaying = _controller.isPlayingNotifier.value;
    notifyListeners();
  }

  void _onQueueChanged() {
    _queue = _controller.queueNotifier.value;
    notifyListeners();
  }

  void _onCurrentIndexChanged() {
    _currentIndex = _controller.currentIndexNotifier.value;
    notifyListeners();
  }

  void _onShuffleChanged() {
    _shuffle = _controller.shuffleNotifier.value;
    notifyListeners();
  }

  Future<void> playPause() => _controller.playPause();
  Future<void> next() => _controller.next();
  Future<void> previous() => _controller.previous();
  Future<void> seek(Duration position) => _controller.seek(position);

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) => _controller.setQueue(tracks, startIndex: startIndex, shuffle: shuffle);

  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false}) =>
      _controller.addTracks(tracks, play: play);

  Future<void> playFromQueueIndex(int orderIndex) =>
      _controller.playFromQueueIndex(orderIndex);

  Future<void> shuffleQueue() => _controller.shuffleQueue();
  Future<void> disableShuffle() => _controller.disableShuffle();

  void setCaptureEnabled(bool enabled) => _transport.setCaptureEnabled(enabled);
  void updateSpectrumSettings(SpectrumSettings settings) =>
      _transport.updateSpectrumSettings(settings);

  Future<List<AudioTrack>> scanFolder(String rootPath) =>
      _controller.scanFolder(rootPath);
  Future<int> playlistSizeBytes() => _controller.playlistSizeBytes();
}
