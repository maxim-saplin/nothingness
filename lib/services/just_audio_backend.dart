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

  // Use maxSkipsOnError to automatically skip tracks that fail to load
  // This handles FileNotFoundException and other source errors natively
  final AudioPlayer _player = AudioPlayer(maxSkipsOnError: 10);
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
  StreamSubscription<PlayerException>? _errorSub;
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();
  @override
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  bool _captureEnabled = true;
  // Track paths of files that failed to load
  final Set<String> _failedTrackPaths = <String>{};
  // Notifier to trigger UI updates when error state changes
  final ValueNotifier<int> _errorStateNotifier = ValueNotifier(0);
  // Track explicit user pause intent to prevent auto-skip from overriding it
  bool _userRequestedPause = false;

  @override
  Future<void> init() async {
    await _playlist.init();

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);

    // Listen to player state - enforce user's pause intent if auto-skip resumed playback
    _playerStateSub = _player.playerStateStream.listen((state) {
      // If user explicitly requested pause but player resumed (e.g., after error auto-skip),
      // immediately re-pause to honor user intent
      if (_userRequestedPause && state.playing) {
        debugPrint('[JustAudioBackend] Enforcing user pause intent after auto-skip');
        _player.pause();
        return;
      }
      isPlayingNotifier.value = state.playing;
      _emitSongInfo();
    });

    // Listen to errorStream for proper error detection (just_audio 0.10.x API)
    // This is the canonical way to detect playback errors like FileNotFoundException
    _errorSub = _player.errorStream.listen((PlayerException e) {
      debugPrint('[JustAudioBackend] Playback error: code=${e.code}, message=${e.message}, index=${e.index}');
      final errorIndex = e.index;
      if (errorIndex != null && 
          errorIndex >= 0 && 
          errorIndex < queueNotifier.value.length) {
        final failedTrack = queueNotifier.value[errorIndex];
        _markTrackAsNotFound(failedTrack.path);
      }
    });
    
    _player.positionStream.listen((_) => _emitSongInfo());
    _player.currentIndexStream.listen((index) {
      if (index != null) {
        // Sync back to PlaylistStore silently if needed
        if (index != _playlist.orderIndexOfCurrent()) {
           _playlist.setCurrentOrderIndex(index);
        }
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
    await _errorSub?.cancel();
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
      _userRequestedPause = false; // User is starting playback
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
      debugPrint('[JustAudioBackend] Marked track as not found: $path');
      // Path was newly added, notify listeners
      // Trigger error state change to force UI refresh
      _errorStateNotifier.value = _errorStateNotifier.value + 1;
      // Also emit song info
      _emitSongInfo();
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
      _userRequestedPause = true;
      await _player.pause();
    } else {
      _userRequestedPause = false;
      await _player.play();
    }
  }

  @override
  Future<void> next() async {
    _userRequestedPause = false; // User navigation implies play intent
    await _player.seekToNext();
  }

  @override
  Future<void> previous() async {
    _userRequestedPause = false; // User navigation implies play intent
    await _player.seekToPrevious();
  }

  @override
  Future<void> playFromQueueIndex(int orderIndex) async {
    await _playlist.setCurrentOrderIndex(orderIndex);
    await _player.seek(Duration.zero, index: orderIndex);

    // If the track is known to be broken, don't auto-play.
    // This prevents a loop of "Select -> Fail -> Skip" when the user taps a broken track.
    // It also allows the user to "pause" by selecting a broken track.
    if (orderIndex >= 0 && orderIndex < queueNotifier.value.length) {
      final track = queueNotifier.value[orderIndex];
      if (_failedTrackPaths.contains(track.path)) {
        if (_player.playing) {
          await _player.pause();
        }
        return;
      }
    }

    if (!_player.playing) {
      _userRequestedPause = false; // User is starting playback
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
    } on PlayerException catch (e) {
      // Handle source loading errors with precise index from exception
      debugPrint('[JustAudioBackend] PlayerException setting sources: code=${e.code}, message=${e.message}, index=${e.index}');
      final errorIndex = e.index ?? startIndex ?? _playlist.orderIndexOfCurrent() ?? 0;
      if (errorIndex >= 0 && errorIndex < tracks.length) {
        final failedTrack = tracks[errorIndex];
        _markTrackAsNotFound(failedTrack.path);
      }
    } catch (e) {
      debugPrint('[JustAudioBackend] Error setting audio source: $e');
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
