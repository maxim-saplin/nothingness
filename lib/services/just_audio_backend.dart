import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;

import '../models/audio_track.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import 'audio_backend.dart';
import 'platform_channels.dart';
import 'playlist_store.dart';

/// Android backend using just_audio + just_audio_background.
class JustAudioBackend implements AudioBackend {
  static const Set<String> supportedExtensions = {
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
    'opus',
  };

  final AudioPlayer _player = AudioPlayer();
  final PlaylistStore _playlist = PlaylistStore();
  final PlatformChannels _platformChannels = PlatformChannels();

  @override
  late final ValueNotifier<List<AudioTrack>> queueNotifier =
      _playlist.queueNotifier;
  @override
  late final ValueNotifier<int?> currentIndexNotifier =
      _playlist.currentOrderIndexNotifier;
  @override
  late final ValueNotifier<bool> shuffleNotifier = _playlist.shuffleNotifier;
  @override
  final ValueNotifier<SongInfo?> songInfoNotifier = ValueNotifier(null);
  @override
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);

  StreamSubscription<List<double>>? _spectrumSub;
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();
  @override
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  bool _captureEnabled = true;

  @override
  Future<void> init() async {
    await _playlist.init();

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);

    // Listen to player state
    _player.playerStateStream.listen((state) {
      isPlayingNotifier.value = state.playing;
      _emitSongInfo();
      
      if (state.processingState == ProcessingState.completed) {
        // Handled by just_audio automatically if using playlist
      }
    });

    _player.positionStream.listen((_) => _emitSongInfo());
    _player.currentIndexStream.listen((index) {
      if (index != null && _player.sequence != null) {
        // Sync back to PlaylistStore silently if needed
        // But PlaylistStore manages order.
        // If we use ConcatenatingAudioSource with the *ordered* list,
        // then player.currentIndex corresponds to queueNotifier index.
        // We need to find the original base index to update PlaylistStore correctly?
        // PlaylistStore.setCurrentOrderIndex expects index in the *ordered* list.
        // So player.currentIndex should match PlaylistStore's order index.
        if (index != _playlist.orderIndexOfCurrent()) {
           _playlist.setCurrentOrderIndex(index);
        }
      }
      _emitSongInfo();
    });
    
    _player.sequenceStateStream.listen((_) => _emitSongInfo());

    // Initialize spectrum if enabled
    if (_captureEnabled) {
      _startSpectrum();
    }
  }

  @override
  Future<void> dispose() async {
    await _stopSpectrum();
    await _player.dispose();
    await _playlist.dispose();
  }

  @override
  void setCaptureEnabled(bool enabled) {
    _captureEnabled = enabled;
    if (enabled) {
      _startSpectrum();
    } else {
      _stopSpectrum();
    }
  }

  @override
  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    await _playlist.setQueue(
      tracks,
      startBaseIndex: startIndex,
      enableShuffle: shuffle,
    );
    await _updatePlayerQueue(startIndex: 0); // PlaylistStore handles shuffle order, so we start at 0 of the ordered list?
    // Wait, setQueue in PlaylistStore sets currentOrderIndex to 0 (if shuffled) or startIndex (if not).
    // So we should seek to currentOrderIndex.
    final initialIndex = _playlist.orderIndexOfCurrent() ?? 0;
    if (_player.sequence != null && _player.sequence!.length > initialIndex) {
      await _player.seek(Duration.zero, index: initialIndex);
      await _player.play();
    }
  }

  @override
  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false}) async {
    await _playlist.addTracks(tracks);
    await _updatePlayerQueue(keepCurrent: true);
    if (play) {
      // If play is requested, we might need to skip to the new tracks.
      // But addTracks usually appends.
      // If we want to play the first added track:
      // Find index of first added track in the ordered list.
      // This is complex with shuffle.
      // For now, just update queue.
    }
  }

  @override
  Future<void> playPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> next() async {
    await _player.seekToNext();
  }

  @override
  Future<void> previous() async {
    await _player.seekToPrevious();
  }

  @override
  Future<void> playFromQueueIndex(int orderIndex) async {
    await _playlist.setCurrentOrderIndex(orderIndex);
    await _player.seek(Duration.zero, index: orderIndex);
    if (!_player.playing) {
      await _player.play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> shuffleQueue() async {
    final currentBaseIndex = _playlist.currentBaseIndex ?? 0;
    await _playlist.reshuffle(keepBaseIndex: currentBaseIndex);
    await _updatePlayerQueue(keepCurrent: true);
  }

  @override
  Future<void> disableShuffle() async {
    final currentBaseIndex = _playlist.currentBaseIndex ?? 0;
    await _playlist.disableShuffle(keepBaseIndex: currentBaseIndex);
    await _updatePlayerQueue(keepCurrent: true);
  }

  @override
  void updateSpectrumSettings(SpectrumSettings settings) {
    _platformChannels.updateSpectrumSettings(settings);
  }

  @override
  Future<int> playlistSizeBytes() {
    return _playlist.persistentSizeBytes();
  }

  @override
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

  Future<void> _updatePlayerQueue({int? startIndex, bool keepCurrent = false}) async {
    final tracks = queueNotifier.value;
    final sources = tracks.map((track) {
      return AudioSource.file(
        track.path,
        tag: MediaItem(
          id: track.path,
          title: track.title,
          artist: track.artist,
          // artUri: ...
        ),
      );
    }).toList();

    try {
      if (keepCurrent) {
        final currentIndex = _playlist.orderIndexOfCurrent();
        final currentPos = _player.position;
        await _player.setAudioSources(sources, initialIndex: currentIndex, initialPosition: currentPos);
      } else {
        await _player.setAudioSources(sources, initialIndex: startIndex);
      }
    } catch (e) {
      debugPrint("Error setting audio source: $e");
    }
  }

  void _emitSongInfo() {
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= queueNotifier.value.length) {
      songInfoNotifier.value = null;
      return;
    }
    
    final track = queueNotifier.value[index];
    songInfoNotifier.value = SongInfo(
      title: track.title,
      artist: track.artist,
      album: '',
      isPlaying: _player.playing,
      position: _player.position.inMilliseconds,
      duration: _player.duration?.inMilliseconds ?? 0,
    );
  }

  Future<void> _startSpectrum() async {
    if (!_captureEnabled) return;
    await _stopSpectrum();
    
    // Wait for session ID to be available
    if (_player.androidAudioSessionId != null) {
       _spectrumSub = _platformChannels.spectrumStream(sessionId: _player.androidAudioSessionId).listen(
        _spectrumController.add,
      );
    } else {
      // Retry or wait?
      // just_audio usually has session ID after setting source.
    }
  }

  Future<void> _stopSpectrum() async {
    await _spectrumSub?.cancel();
    _spectrumSub = null;
  }
}
