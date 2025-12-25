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
  SpectrumSettings _settings = const SpectrumSettings();

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
  StreamSubscription<int?>? _sessionIdSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();
  @override
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  bool _captureEnabled = true;
  // Track paths of files that failed to load
  final Set<String> _failedTrackPaths = <String>{};
  // Track previous index to detect skips (which indicate errors)
  int? _previousIndex;
  // Notifier to trigger UI updates when error state changes
  final ValueNotifier<int> _errorStateNotifier = ValueNotifier(0);

  @override
  Future<void> init() async {
    await _playlist.init();

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);

    // Listen to player state
    _playerStateSub = _player.playerStateStream.listen((state) {
      isPlayingNotifier.value = state.playing;
      
      // Detect when player gets stuck in idle state while trying to play
      // This can indicate a failed source
      final currentIndex = _player.currentIndex;
      if (state.processingState == ProcessingState.idle && 
          state.playing && 
          currentIndex != null &&
          currentIndex >= 0 &&
          currentIndex < queueNotifier.value.length) {
        final track = queueNotifier.value[currentIndex];
        // Check if this track hasn't been marked as failed yet
        if (!_failedTrackPaths.contains(track.path)) {
          // Player is trying to play but stuck in idle - likely a failed source
          debugPrint('[JustAudioBackend] Player stuck in idle state for track: ${track.path}');
          _handlePlaybackError();
        }
      }
      
      _emitSongInfo();
      
      if (state.processingState == ProcessingState.completed) {
        // Handled by just_audio automatically if using playlist
      }
    });
    
    _player.positionStream.listen((_) => _emitSongInfo());
    _player.currentIndexStream.listen((index) {
      if (index != null) {
        // Sync back to PlaylistStore silently if needed
        if (index != _playlist.orderIndexOfCurrent()) {
           _playlist.setCurrentOrderIndex(index);
        }
        
        // Detect when just_audio skips tracks (indicates error)
        if (_previousIndex != null && index > _previousIndex! + 1) {
          // Track was skipped - mark skipped tracks as not found
          for (int i = _previousIndex! + 1; i < index; i++) {
            if (i >= 0 && i < queueNotifier.value.length) {
              final skippedTrack = queueNotifier.value[i];
              _failedTrackPaths.add(skippedTrack.path);
              _markTrackAsNotFound(skippedTrack.path);
            }
          }
        }
        _previousIndex = index;
      } else {
        _previousIndex = null;
      }
      _emitSongInfo();
    });
    
    _player.sequenceStateStream.listen((sequenceState) {
      _emitSongInfo();
    });

    // Listen for audio session id availability and restart spectrum capture when it changes.
    _sessionIdSub = _player.androidAudioSessionIdStream.listen((sessionId) {
      if (!_captureEnabled) return;
      _startSpectrum(sessionId: sessionId);
    });

    // Restore queue into player if playlist was persisted from previous session.
    if (queueNotifier.value.isNotEmpty) {
      debugPrint('[JustAudioBackend] init: restoring ${queueNotifier.value.length} tracks from persistence');
      await _updatePlayerQueue(startIndex: _playlist.orderIndexOfCurrent() ?? 0);
    }

    // Initialize spectrum if enabled
    if (_captureEnabled) {
      _startSpectrum(sessionId: _player.androidAudioSessionId);
    }
  }

  @override
  Future<void> dispose() async {
    await _stopSpectrum();
    await _playerStateSub?.cancel();
    await _sessionIdSub?.cancel();
    await _player.dispose();
    await _playlist.dispose();
  }

  @override
  void setCaptureEnabled(bool enabled) {
    _captureEnabled = enabled;
    if (enabled) {
      _startSpectrum(sessionId: _player.androidAudioSessionId);
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
    // Clear failed tracks when setting new queue
    _failedTrackPaths.clear();
    await _playlist.setQueue(
      tracks,
      startBaseIndex: startIndex,
      enableShuffle: shuffle,
    );
    await _updatePlayerQueue(startIndex: 0); // PlaylistStore handles shuffle order, so we start at 0 of the ordered list?
    // Wait, setQueue in PlaylistStore sets currentOrderIndex to 0 (if shuffled) or startIndex (if not).
    // So we should seek to currentOrderIndex.
    final initialIndex = _playlist.orderIndexOfCurrent() ?? 0;
    debugPrint('[JustAudioBackend] setQueue: sequence.length=${_player.sequence.length}, initialIndex=$initialIndex');
    if (_player.sequence.isNotEmpty && _player.sequence.length > initialIndex) {
      await _player.seek(Duration.zero, index: initialIndex);
      await _player.play();
      debugPrint('[JustAudioBackend] setQueue: started playback');
    } else {
      debugPrint('[JustAudioBackend] setQueue: sequence empty or invalid index');
    }
  }

  /// Returns the queue with isNotFound flags set based on failed playback attempts
  List<AudioTrack> getQueueWithNotFoundFlags() {
    return queueNotifier.value.map((track) {
      if (_failedTrackPaths.contains(track.path)) {
        return track.copyWith(isNotFound: true);
      }
      return track;
    }).toList();
  }

  /// Get the error state notifier for listening to error state changes
  ValueNotifier<int> get errorStateNotifier => _errorStateNotifier;

  /// Check if a track path has failed to load
  bool isTrackNotFound(String path) {
    return _failedTrackPaths.contains(path);
  }

  void _markTrackAsNotFound(String path) {
    if (_failedTrackPaths.add(path)) {
      // Path was newly added, notify listeners
      // Trigger error state change to force UI refresh
      _errorStateNotifier.value = _errorStateNotifier.value + 1;
      // Also emit song info
      _emitSongInfo();
    }
  }

  /// Handle playback error - mark current track as not found and skip to next
  Future<void> _handlePlaybackError() async {
    final currentIndex = _player.currentIndex;
    if (currentIndex == null || currentIndex < 0 || currentIndex >= queueNotifier.value.length) {
      return;
    }
    
    final failedTrack = queueNotifier.value[currentIndex];
    debugPrint('[JustAudioBackend] Playback error detected for track: ${failedTrack.path}');
    
    // Mark track as not found
    _markTrackAsNotFound(failedTrack.path);
    
    // Skip to next track
    try {
      await _player.seekToNext();
      debugPrint('[JustAudioBackend] Skipped to next track after error');
    } catch (e) {
      debugPrint('[JustAudioBackend] Error skipping to next track: $e');
      // If seekToNext fails, try using next() method
      try {
        await next();
      } catch (e2) {
        debugPrint('[JustAudioBackend] Error calling next(): $e2');
      }
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
    _settings = settings;
    _platformChannels.updateSpectrumSettings(settings);
    // Restart capture when source/decay/noise gate changes.
    if (_captureEnabled) {
      _startSpectrum(sessionId: _player.androidAudioSessionId);
    }
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
    debugPrint('[JustAudioBackend] _updatePlayerQueue: ${tracks.length} tracks, startIndex=$startIndex, keepCurrent=$keepCurrent');
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
        debugPrint('[JustAudioBackend] _updatePlayerQueue: set ${sources.length} sources (keepCurrent)');
      } else {
        await _player.setAudioSources(sources, initialIndex: startIndex);
        debugPrint('[JustAudioBackend] _updatePlayerQueue: set ${sources.length} sources at index $startIndex');
      }
    } catch (e) {
      debugPrint("Error setting audio source: $e");
      // If setting sources fails, mark the current track as not found
      final currentIndex = startIndex ?? _playlist.orderIndexOfCurrent() ?? 0;
      if (currentIndex >= 0 && currentIndex < tracks.length) {
        final failedTrack = tracks[currentIndex];
        _markTrackAsNotFound(failedTrack.path);
      }
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

  Future<void> _startSpectrum({int? sessionId}) async {
    if (!_captureEnabled) return;
    await _stopSpectrum();

    // Choose source based on settings: player (via session id) or microphone (null).
    final bool useMic = _settings.audioSource == AudioSourceMode.microphone;
    final int? resolvedSessionId = useMic
        ? null
        : (sessionId ?? _player.androidAudioSessionId);

    // If we want player output but don't have a session yet, wait for the
    // sessionId stream listener to fire instead of falling back to mic.
    if (!useMic && resolvedSessionId == null) {
      return;
    }

    _spectrumSub = _platformChannels
        .spectrumStream(sessionId: resolvedSessionId)
        .listen(_spectrumController.add);
  }

  Future<void> _stopSpectrum() async {
    await _spectrumSub?.cancel();
    _spectrumSub = null;
  }
}
