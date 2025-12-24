import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import '../models/audio_track.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import 'playlist_store.dart';
import 'soloud_spectrum_provider.dart';
import 'spectrum_provider.dart';

/// Centralized audio player/queue + spectrum capture from player output.
class AudioPlayerService {
  AudioPlayerService._internal();
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;

  static const Set<String> supportedExtensions = {
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
    'opus',
  };

  final SoLoud _soloud = SoLoud.instance;
  final PlaylistStore _playlist = PlaylistStore();

  late final ValueNotifier<List<AudioTrack>> queueNotifier =
      _playlist.queueNotifier;
  late final ValueNotifier<int?> currentIndexNotifier =
      _playlist.currentOrderIndexNotifier;
  late final ValueNotifier<bool> shuffleNotifier = _playlist.shuffleNotifier;
  final ValueNotifier<SongInfo?> songInfoNotifier = ValueNotifier(null);

  /// Immediate play intent state - updates before track actually loads.
  /// Use this for UI responsiveness during track loading/skipping.
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);

  SpectrumProvider? _spectrumProvider;
  StreamSubscription<List<double>>? _spectrumSub;
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  SoundHandle? _currentHandle;
  AudioSource? _currentSource;
  Timer? _positionTimer;
  bool _captureEnabled = true;

  /// Flag to cancel the skip-on-error loop in _playOrderIndex.
  bool _cancelPlayback = false;

  Future<void> init() async {
    await _playlist.init();

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

    await _emitSongInfo(force: true);
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
    await _playlist.dispose();
  }

  void setCaptureEnabled(bool enabled) {
    _captureEnabled = enabled;
    if (!enabled) {
      _stopSpectrum();
    } else {
      _startSpectrum();
    }
  }

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    await _playlist.setQueue(
      tracks,
      startBaseIndex: startIndex,
      enableShuffle: shuffle,
    );
    final orderIndex = currentIndexNotifier.value ?? 0;
    await _playOrderIndex(orderIndex);
  }

  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false}) async {
    if (tracks.isEmpty) return;
    final firstNewBaseIndex = _playlist.baseLength;
    await _playlist.addTracks(tracks);
    if (play || _currentHandle == null) {
      final orderIndex = _playlist.orderIndexForBase(firstNewBaseIndex) ?? 0;
      await _playOrderIndex(orderIndex);
    }
  }

  Future<void> playPause() async {
    // If we have a queue but nothing is loaded yet, start playback from the
    // current (or first) track instead of silently doing nothing.
    if (_currentHandle == null) {
      final orderIndex = currentIndexNotifier.value ?? 0;
      if (_playlist.length > 0) {
        await _playOrderIndex(orderIndex);
      }
      return;
    }

    // If we're in the middle of skipping through bad files, cancel that loop
    if (_cancelPlayback == false && isPlayingNotifier.value) {
      _cancelPlayback = true;
      isPlayingNotifier.value = false;
      _emitSongInfo();
      return;
    }

    final paused = _soloud.getPause(_currentHandle!);
    _soloud.setPause(_currentHandle!, !paused);
    isPlayingNotifier.value = paused; // Will be playing if was paused
    if (!paused) {
      _stopSpectrum();
    } else {
      _startSpectrum();
    }
    _emitSongInfo();
  }

  Future<void> next() async {
    final nextIdx = _playlist.nextOrderIndex();
    if (nextIdx != null) {
      await _playOrderIndex(nextIdx);
    }
  }

  Future<void> previous() async {
    final prevIdx = _playlist.previousOrderIndex();
    if (prevIdx != null) {
      await _playOrderIndex(prevIdx);
    }
  }

  Future<void> playFromQueueIndex(int orderIndex) async {
    final currentIdx = currentIndexNotifier.value;
    if (currentIdx == orderIndex && _currentHandle != null) {
      await playPause();
      return;
    }
    await _playOrderIndex(orderIndex);
  }

  Future<void> shuffleQueue() async {
    await _playlist.reshuffle(
      keepBaseIndex: _playlist.currentBaseIndex ?? 0,
    );
    final idx = currentIndexNotifier.value ?? 0;
    await _playOrderIndex(idx);
  }

  Future<void> disableShuffle() async {
    final baseIndex = _playlist.currentBaseIndex ?? 0;
    await _playlist.disableShuffle(keepBaseIndex: baseIndex);
    final idx = _playlist.orderIndexForBase(baseIndex) ?? baseIndex;
    await _playOrderIndex(idx);
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

  Future<int> playlistSizeBytes() {
    return _playlist.persistentSizeBytes();
  }

  Future<void> _playOrderIndex(int initialOrderIndex) async {
    if (_playlist.length == 0) return;

    // Reset cancellation flag at start of new playback attempt
    _cancelPlayback = false;

    // Immediately signal play intent for UI responsiveness
    isPlayingNotifier.value = true;

    int? currentOrderIndex = initialOrderIndex;
    int attempts = 0;
    // Limit attempts to playlist length to prevent infinite loops if all files are bad
    final maxAttempts = _playlist.length;

    while (attempts < maxAttempts && currentOrderIndex != null) {
      // Check if user requested cancellation (e.g., clicked pause)
      if (_cancelPlayback) {
        debugPrint('Playback cancelled by user');
        isPlayingNotifier.value = false;
        _emitSongInfo(force: true);
        return;
      }

      if (currentOrderIndex < 0 || currentOrderIndex >= _playlist.length) {
        break;
      }

      await _playlist.setCurrentOrderIndex(currentOrderIndex);
      final track = _playlist.trackForOrderIndex(currentOrderIndex);
      if (track == null) {
        break;
      }

      try {
        if (_currentHandle != null) {
          await _soloud.stop(_currentHandle!);
        }
      } catch (e) {
        debugPrint('Error stopping handle: $e');
      }
      _currentHandle = null;

      try {
        if (_currentSource != null) {
          await _soloud.disposeSource(_currentSource!);
        }
      } catch (e) {
        debugPrint('Error disposing source: $e');
      }
      _currentSource = null;

      final completer = Completer<bool>();

      runZonedGuarded(
        () async {
          try {
            if (p.extension(track.path).toLowerCase() == '.opus') {
              final file = File(track.path);
              final bytes = await file.readAsBytes();

              _currentSource = _soloud.setBufferStream(
                bufferingType: BufferingType.preserved,
                format: BufferType.auto,
                channels: Channels.stereo,
                sampleRate: 44100,
              );

              final handle = await _soloud.play(_currentSource!, paused: false);
              _currentHandle = handle;

              _soloud.addAudioDataStream(_currentSource!, bytes);
              _soloud.setDataIsEnded(_currentSource!);
            } else {
              _currentSource = await _soloud.loadFile(track.path);
              final handle = await _soloud.play(_currentSource!, paused: false);
              _currentHandle = handle;
            }

            try {
              await _startSpectrum();
            } catch (e) {
              debugPrint('Spectrum start error: $e');
            }
            if (!completer.isCompleted) {
              completer.complete(true);
            }
          } catch (e) {
            debugPrint('Play error for ${track.path}: $e');
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        },
        (error, stackTrace) {
          debugPrint('Zone error for ${track.path}: $error');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
      );

      final success = await completer.future;
      if (success) {
        isPlayingNotifier.value = true;
        _emitSongInfo(force: true);
        return;
      }

      attempts++;
      currentOrderIndex = _playlist.nextOrderIndex();
      if (currentOrderIndex != null) {
        debugPrint('Skipping to next track: $currentOrderIndex');
      }
    }

    isPlayingNotifier.value = false;
    _emitSongInfo(force: true);
  }

  Future<void> _startSpectrum() async {
    if (!_captureEnabled) return;
    await _spectrumProvider?.start();
  }

  Future<void> _stopSpectrum() async {
    await _spectrumProvider?.stop();
  }

  Future<void> _stopAfterQueueEnd() async {
    if (_currentHandle != null) {
      await _soloud.stop(_currentHandle!);
      _currentHandle = null;
    }
    if (_currentSource != null) {
      await _soloud.disposeSource(_currentSource!);
      _currentSource = null;
    }
    isPlayingNotifier.value = false;
    await _stopSpectrum();
    await _emitSongInfo(force: true);
  }

  Future<void> _emitSongInfo({bool force = false}) async {
    final idx = currentIndexNotifier.value;
    final track = idx == null ? null : _playlist.trackForOrderIndex(idx);
    if (idx == null || track == null) {
      songInfoNotifier.value = null;
      return;
    }
    final handle = _currentHandle;
    Duration position = Duration.zero;
    Duration duration = Duration.zero;
    bool isPlaying = isPlayingNotifier.value;

    if (handle != null) {
      try {
        position = _soloud.getPosition(handle);
        if (_currentSource != null) {
          duration = _soloud.getLength(_currentSource!);
        }
        isPlaying = !_soloud.getPause(handle);

        if (!force && duration > Duration.zero && position >= duration) {
          final nextIdx = _playlist.nextOrderIndex();
          if (nextIdx != null) {
            await _playOrderIndex(nextIdx);
          } else {
            await _stopAfterQueueEnd();
          }
          return;
        }
      } catch (e) {
        debugPrint('Song info error: $e');
      }
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

    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).replaceAll('.', '').toLowerCase();
      if (!supportedExtensions.contains(ext)) continue;
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
