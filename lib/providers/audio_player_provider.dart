import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/audio_player_service.dart';

/// Provider wrapper for AudioPlayerService.
/// Exposes reactive state via ChangeNotifier for use with Provider.
class AudioPlayerProvider extends ChangeNotifier {
  final AudioPlayerService _service = AudioPlayerService();

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
  Stream<List<double>> get spectrumStream => _service.spectrumStream;

  // Pass-through to service
  static Set<String> get supportedExtensions =>
      AudioPlayerService.supportedExtensions;

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Initialize the audio player service and set up listeners.
  Future<void> init() async {
    if (_initialized) return;

    await _service.init();

    _service.songInfoNotifier.addListener(_onSongInfoChanged);
    _service.isPlayingNotifier.addListener(_onIsPlayingChanged);
    _service.queueNotifier.addListener(_onQueueChanged);
    _service.currentIndexNotifier.addListener(_onCurrentIndexChanged);
    _service.shuffleNotifier.addListener(_onShuffleChanged);

    _songInfo = _service.songInfoNotifier.value;
    _isPlaying = _service.isPlayingNotifier.value;
    _queue = _service.queueNotifier.value;
    _currentIndex = _service.currentIndexNotifier.value;
    _shuffle = _service.shuffleNotifier.value;

    _spectrumSubscription = _service.spectrumStream.listen((data) {
      _spectrumData = data;
      notifyListeners();
    });

    _initialized = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.songInfoNotifier.removeListener(_onSongInfoChanged);
    _service.isPlayingNotifier.removeListener(_onIsPlayingChanged);
    _service.queueNotifier.removeListener(_onQueueChanged);
    _service.currentIndexNotifier.removeListener(_onCurrentIndexChanged);
    _service.shuffleNotifier.removeListener(_onShuffleChanged);
    _spectrumSubscription?.cancel();
    _service.dispose();
    super.dispose();
  }

  void _onSongInfoChanged() {
    _songInfo = _service.songInfoNotifier.value;
    notifyListeners();
  }

  void _onIsPlayingChanged() {
    _isPlaying = _service.isPlayingNotifier.value;
    notifyListeners();
  }

  void _onQueueChanged() {
    _queue = _service.queueNotifier.value;
    notifyListeners();
  }

  void _onCurrentIndexChanged() {
    _currentIndex = _service.currentIndexNotifier.value;
    notifyListeners();
  }

  void _onShuffleChanged() {
    _shuffle = _service.shuffleNotifier.value;
    notifyListeners();
  }

  Future<void> playPause() => _service.playPause();
  Future<void> next() => _service.next();
  Future<void> previous() => _service.previous();
  Future<void> seek(Duration position) => _service.seek(position);

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) =>
      _service.setQueue(tracks, startIndex: startIndex, shuffle: shuffle);

  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false}) =>
      _service.addTracks(tracks, play: play);

  Future<void> playFromQueueIndex(int orderIndex) =>
      _service.playFromQueueIndex(orderIndex);

  Future<void> shuffleQueue() => _service.shuffleQueue();
  Future<void> disableShuffle() => _service.disableShuffle();

  void setCaptureEnabled(bool enabled) => _service.setCaptureEnabled(enabled);
  void updateSpectrumSettings(SpectrumSettings settings) =>
      _service.updateSpectrumSettings(settings);

  Future<List<AudioTrack>> scanFolder(String rootPath) =>
      _service.scanFolder(rootPath);
  Future<int> playlistSizeBytes() => _service.playlistSizeBytes();
}
