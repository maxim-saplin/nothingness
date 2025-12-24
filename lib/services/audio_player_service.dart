import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import 'soloud_spectrum_provider.dart';
import 'spectrum_provider.dart';

class AudioTrack {
  final String path;
  final String title;
  final String artist;
  final Duration? duration;

  const AudioTrack({
    required this.path,
    required this.title,
    this.artist = 'Local File',
    this.duration,
  });
}

/// Centralized audio player/queue + spectrum capture from player output.
class AudioPlayerService {
  AudioPlayerService._internal();
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;

  final SoLoud _soloud = SoLoud.instance;

  final ValueNotifier<List<AudioTrack>> queueNotifier = ValueNotifier([]);
  final ValueNotifier<int?> currentIndexNotifier = ValueNotifier(null);
  final ValueNotifier<SongInfo?> songInfoNotifier = ValueNotifier(null);

  SpectrumProvider? _spectrumProvider;
  StreamSubscription<List<double>>? _spectrumSub;
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  SoundHandle? _currentHandle;
  AudioSource? _currentSource;
  Timer? _positionTimer;
  bool _captureEnabled = true;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);

    await _soloud.init();
    _soloud.setVisualizationEnabled(true);

    _spectrumProvider = SoLoudSpectrumProvider(
      soloud: _soloud,
      handleProvider: () async => _currentHandle,
      initialSettings: const SpectrumSettings(),
    );

    _spectrumSub = _spectrumProvider!.spectrumStream.listen(
      _spectrumController.add,
    );

    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _emitSongInfo(),
    );
  }

  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _stopSpectrum();
    if (_currentHandle != null) {
      await _soloud.stop(_currentHandle!);
    }
    if (_currentSource != null) {
      await _soloud.disposeSource(_currentSource!);
    }
    await _spectrumSub?.cancel();
  }

  void setCaptureEnabled(bool enabled) {
    _captureEnabled = enabled;
    if (!enabled) {
      _stopSpectrum();
    } else {
      _startSpectrum();
    }
  }

  Future<void> setQueue(List<AudioTrack> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    queueNotifier.value = List.unmodifiable(tracks);
    currentIndexNotifier.value = startIndex;
    await _playIndex(startIndex);
  }

  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false}) async {
    if (tracks.isEmpty) return;
    final updated = [...queueNotifier.value, ...tracks];
    queueNotifier.value = List.unmodifiable(updated);
    if (play || _currentHandle == null) {
      await _playIndex(queueNotifier.value.length - tracks.length);
    }
  }

  Future<void> playPause() async {
    if (_currentHandle == null) return;
    final paused = _soloud.getPause(_currentHandle!);
    _soloud.setPause(_currentHandle!, !paused);
    if (!paused) {
      _stopSpectrum();
    } else {
      _startSpectrum();
    }
    _emitSongInfo();
  }

  Future<void> next() async {
    final idx = currentIndexNotifier.value;
    if (idx == null) return;
    final nextIdx = idx + 1;
    if (nextIdx < queueNotifier.value.length) {
      await _playIndex(nextIdx);
    }
  }

  Future<void> previous() async {
    final idx = currentIndexNotifier.value;
    if (idx == null) return;
    final prevIdx = idx - 1;
    if (prevIdx >= 0) {
      await _playIndex(prevIdx);
    }
  }

  Future<void> seek(Duration position) async {
    if (_currentHandle == null) return;
    _soloud.seek(_currentHandle!, position);
    _emitSongInfo();
  }

  void updateSpectrumSettings(SpectrumSettings settings) {
    _spectrumProvider?.updateSettings(settings);
    _soloud.setFftSmoothing(settings.decaySpeed.value.clamp(0.0, 1.0));
  }

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= queueNotifier.value.length) return;

    currentIndexNotifier.value = index;
    final track = queueNotifier.value[index];

    if (_currentHandle != null) {
      await _soloud.stop(_currentHandle!);
    }
    if (_currentSource != null) {
      await _soloud.disposeSource(_currentSource!);
    }
    _currentHandle = null;
    _currentSource = null;

    try {
      _currentSource = await _soloud.loadFile(track.path);
      final handle = await _soloud.play(_currentSource!, paused: false);
      _currentHandle = handle;
      _startSpectrum();
    } catch (e) {
      debugPrint('Play error: $e');
    }

    _emitSongInfo(force: true);
  }

  Future<void> _startSpectrum() async {
    if (!_captureEnabled) return;
    await _spectrumProvider?.start();
  }

  Future<void> _stopSpectrum() async {
    await _spectrumProvider?.stop();
  }

  Future<void> _emitSongInfo({bool force = false}) async {
    final idx = currentIndexNotifier.value;
    if (idx == null || idx >= queueNotifier.value.length) {
      songInfoNotifier.value = null;
      return;
    }

    final track = queueNotifier.value[idx];
    final handle = _currentHandle;
    if (handle == null) {
      songInfoNotifier.value = SongInfo(
        title: track.title,
        artist: track.artist,
        album: '',
        isPlaying: false,
        position: 0,
        duration: (track.duration ?? Duration.zero).inMilliseconds,
      );
      return;
    }

    Duration position = Duration.zero;
    Duration duration = Duration.zero;
    bool isPlaying = true;

    try {
      position = _soloud.getPosition(handle);
      if (_currentSource != null) {
        duration = _soloud.getLength(_currentSource!);
      }
      isPlaying = !_soloud.getPause(handle);

      if (!force && duration > Duration.zero && position >= duration) {
        await next();
        return;
      }
    } catch (e) {
      debugPrint('Song info error: $e');
    }

    songInfoNotifier.value = SongInfo(
      title: track.title,
      artist: track.artist,
      album: '',
      isPlaying: isPlaying,
      position: position.inMilliseconds,
      duration: duration.inMilliseconds,
    );
  }

  Future<List<AudioTrack>> scanFolder(String rootPath) async {
    final List<AudioTrack> tracks = [];
    final directory = Directory(rootPath);
    if (!await directory.exists()) return tracks;

    final supported = <String>{'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'};

    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).replaceAll('.', '').toLowerCase();
      if (!supported.contains(ext)) continue;
      final title = p.basenameWithoutExtension(entity.path);
      tracks.add(
        AudioTrack(
          path: entity.path,
          title: title,
        ),
      );
    }

    tracks.sort((a, b) => a.title.compareTo(b.title));
    return tracks;
  }
}
