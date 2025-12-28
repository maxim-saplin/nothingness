import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/audio_track.dart';
import '../models/spectrum_settings.dart';
import '../models/supported_extensions.dart';
import 'audio_transport.dart';
import 'platform_channels.dart';

/// Thin wrapper around just_audio AudioPlayer.
/// Implements AudioTransport interface - no queue management, no skip logic.
class JustAudioTransport implements AudioTransport {
  static const Set<String> supportedExtensions =
      SupportedExtensions.supportedExtensions;
  // Remove maxSkipsOnError - handle skipping in PlaybackController
  final AudioPlayer _player = AudioPlayer(maxSkipsOnError: 0);
  final StreamController<TransportEvent> _eventController =
      StreamController<TransportEvent>.broadcast();

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<PlayerException>? _errorSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<int?>? _sessionIdSub;
  StreamSubscription<List<double>>? _spectrumSub;
  String? _currentPath;

  final PlatformChannels _platformChannels = PlatformChannels();
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();
  SpectrumSettings _settings = const SpectrumSettings();
  bool _captureEnabled = true;

  // Queue management for MediaSession
  List<AudioSource>? _queueSources;
  final Map<String, int> _pathToIndex = {};

  @override
  Stream<TransportEvent> get eventStream => _eventController.stream;

  @override
  Future<Duration> get position async => _player.position;

  @override
  Future<Duration> get duration async {
    final d = _player.duration;
    return d ?? Duration.zero;
  }

  @override
  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);

    // Listen to player state changes
    _playerStateSub = _player.playerStateStream.listen((state) {
      // Emit ended event when track completes
      if (state.processingState == ProcessingState.completed) {
        _eventController.add(TransportEndedEvent(path: _currentPath));
      }
    });

    // Listen to errors
    _errorSub = _player.errorStream.listen((PlayerException e) {
      debugPrint(
        '[JustAudioTransport] Error: code=${e.code}, message=${e.message}',
      );
      _eventController.add(TransportErrorEvent(path: _currentPath, error: e));
    });

    // Emit position updates periodically
    _positionSub = _player.positionStream.listen((position) {
      _eventController.add(TransportPositionEvent(position: position));
    });

    // Listen for audio session id availability and restart spectrum capture when it changes.
    _sessionIdSub = _player.androidAudioSessionIdStream.listen((sessionId) {
      if (_captureEnabled) {
        _startSpectrum();
      }
    });

    // Initialize spectrum if enabled
    if (_captureEnabled) {
      _startSpectrum();
    }
  }

  Future<void> _startSpectrum() async {
    if (!_captureEnabled) return;
    await _stopSpectrum();

    final bool useMic = _settings.audioSource == AudioSourceMode.microphone;
    final int? sessionId = useMic ? null : _player.androidAudioSessionId;

    // If we want player output but don't have a session yet, wait for the
    // sessionId stream listener to fire instead of falling back to mic.
    if (!useMic && sessionId == null) {
      return;
    }

    _spectrumSub = _platformChannels
        .spectrumStream(sessionId: sessionId)
        .listen(_spectrumController.add);
  }

  Future<void> _stopSpectrum() async {
    await _spectrumSub?.cancel();
    _spectrumSub = null;
  }

  @override
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  @override
  void updateSpectrumSettings(SpectrumSettings settings) {
    _settings = settings;
    _platformChannels.updateSpectrumSettings(settings);
    if (_captureEnabled) {
      _startSpectrum();
    }
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
  Future<void> dispose() async {
    await _playerStateSub?.cancel();
    await _errorSub?.cancel();
    await _positionSub?.cancel();
    await _sessionIdSub?.cancel();
    await _stopSpectrum();
    await _player.dispose();
    await _eventController.close();
    await _spectrumController.close();
  }

  /// Set the full queue for MediaSession support.
  /// This populates the AudioPlayer's queue so Android's MediaSession
  /// can advertise next/previous actions.
  Future<void> setQueue(List<AudioTrack> tracks) async {
    if (tracks.isEmpty) {
      _pathToIndex.clear();
      _queueSources = null;
      return;
    }

    _pathToIndex.clear();

    // Build sources with MediaItems
    final sources = <AudioSource>[];
    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      _pathToIndex[track.path] = i;

      final tag = MediaItem(
        id: track.path,
        title: track.title,
        artist: track.artist,
      );

      final bool isContentUri = track.path.startsWith('content://');
      final AudioSource source = isContentUri
          ? AudioSource.uri(Uri.parse(track.path), tag: tag)
          : AudioSource.file(track.path, tag: tag);

      sources.add(source);
    }

    // Store sources for later use
    _queueSources = sources;

    // Set the queue sources if player is initialized
    // If not initialized yet, it will be set on first load()
    if (_player.sequence.isNotEmpty || _currentPath != null) {
      try {
        final currentIndex = _pathToIndex[_currentPath] ?? 0;
        final currentPos = _player.position;
        await _player.setAudioSources(
          sources,
          initialIndex: currentIndex,
          initialPosition: currentPos,
        );
      } catch (e) {
        debugPrint('[JustAudioTransport] Error setting queue: $e');
      }
    }
  }

  @override
  Future<void> load(String path, {String? title, String? artist}) async {
    try {
      _currentPath = path;

      // If we have queue sources, seek to the track in the queue
      if (_queueSources != null && _pathToIndex.containsKey(path)) {
        final index = _pathToIndex[path]!;

        // If queue sources aren't set yet, set them now
        if (_player.sequence.isEmpty) {
          await _player.setAudioSources(_queueSources!, initialIndex: index);
        } else {
          // Seek to the track in the existing queue
          await _player.seek(Duration.zero, index: index);
        }

        _eventController.add(TransportLoadedEvent(path: path));
        return;
      }

      // Fallback: load single source if queue not available
      // This shouldn't happen in normal operation, but keeps compatibility
      final tag = MediaItem(
        id: path,
        title: title ?? 'Unknown Title',
        artist: artist ?? 'Unknown Artist',
      );

      final bool isContentUri = path.startsWith('content://');
      final AudioSource source = isContentUri
          ? AudioSource.uri(Uri.parse(path), tag: tag)
          : AudioSource.file(path, tag: tag);

      await _player.setAudioSource(source);
      _eventController.add(TransportLoadedEvent(path: path));
    } catch (e) {
      debugPrint('[JustAudioTransport] Error loading $path: $e');
      _eventController.add(TransportErrorEvent(path: path, error: e));
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }
}
