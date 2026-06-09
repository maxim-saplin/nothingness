import 'dart:async';

import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/services/audio_transport.dart';

/// Mock implementation of AudioTransport for testing PlaybackController.
/// 
/// This allows tests to control transport behavior:
/// - Simulate successful/failed loads
/// - Emit events (ended, error, loaded)
/// - Control position/duration reporting
class MockAudioTransport implements AudioTransport {
  final StreamController<TransportEvent> _eventController =
      StreamController<TransportEvent>.broadcast();
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();

  // Controllable state
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _loadedPath;
  bool _isPlaying = false;
  
  // Configuration for test scenarios
  final Set<String> pathsToFailOnLoad = {};
  // Paths whose load throws a *transient*-classified error (string matches
  // isTransientLoadError) — i.e. should be retried, not flagged not-found.
  final Set<String> pathsToFailTransiently = {};
  bool autoEmitLoadedEvent = true;
  Duration loadDelay = Duration.zero;
  bool failPlayWhenUnloaded = false;
  
  // Call tracking for verification
  final List<String> loadCalls = [];
  final List<String> preloadCalls = [];
  final List<String> playCalls = [];
  final List<String> pauseCalls = [];
  final List<Duration> seekCalls = [];
  int suspendTimerCalls = 0;
  int resumeTimerCalls = 0;
  int positionReadCount = 0;
  int durationReadCount = 0;
  
  @override
  Stream<TransportEvent> get eventStream => _eventController.stream;

  @override
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  @override
  Future<Duration> get position async {
    positionReadCount += 1;
    return _position;
  }

  @override
  Future<Duration> get duration async {
    durationReadCount += 1;
    return _duration;
  }

  @override
  Future<void> init() async {
    // No-op for mock
  }

  @override
  Future<void> dispose() async {
    await _eventController.close();
    await _spectrumController.close();
  }

  @override
  Future<void> seekWithinCurrentTrack(Duration position, {int? generation}) async {
    seekCalls.add(position);
    _position = position;
  }

  @override
  Future<void> cancelGeneration(int generation) async {}

  @override
  Future<void> setPlaybackTarget(String path, {String? title, String? artist, int? generation}) async {
    loadCalls.add(path);
    if (loadDelay > Duration.zero) {
      await Future.delayed(loadDelay);
    }
    
    if (pathsToFailOnLoad.contains(path)) {
      throw StateError('File not found: $path');
    }
    if (pathsToFailTransiently.contains(path)) {
      throw StateError('Connection aborted 10000000');
    }

    _loadedPath = path;
    if (autoEmitLoadedEvent) {
      _eventController.add(TransportLoadedEvent(path: path));
    }
  }

  @override
  Future<void> setAudibleState(bool audible, {int? generation}) async {
    if (audible) {
      if (failPlayWhenUnloaded && _loadedPath == null) {
        throw StateError('Cannot play without loaded source');
      }
      playCalls.add(_loadedPath ?? 'unknown');
    } else {
      pauseCalls.add(_loadedPath ?? 'unknown');
    }
    _isPlaying = audible;
  }

  @override
  @Deprecated('Use setPlaybackTarget and setAudibleState(true) instead')
  Future<void> load(String path, {String? title, String? artist}) async {
    loadCalls.add(path);
    
    if (loadDelay > Duration.zero) {
      await Future.delayed(loadDelay);
    }
    
    if (pathsToFailTransiently.contains(path)) {
      _loadedPath = path;
      final error = Exception('connection aborted: $path');
      _eventController.add(TransportErrorEvent(path: path, error: error));
      throw error;
    }

    if (pathsToFailOnLoad.contains(path)) {
      _loadedPath = path;  // Still set path so error event has context
      final error = Exception('File not found: $path');
      _eventController.add(TransportErrorEvent(
        path: path,
        error: error,
      ));
      // Match real transport behavior: emit error event AND throw
      // This is critical because PlaybackController has both a catch block
      // AND a stream listener that handle errors - we need to test both paths
      throw error;
    }
    
    _loadedPath = path;
    _position = Duration.zero;
    _duration = const Duration(minutes: 3); // Default 3 min track
    
    if (autoEmitLoadedEvent) {
      _eventController.add(TransportLoadedEvent(path: path));
    }
  }

  @override
  Future<void> preload(String path) async {
    preloadCalls.add(path);
  }

  @override
  Future<void> play() async {
    if (failPlayWhenUnloaded && _loadedPath == null) {
      throw StateError('No source loaded. Call load() first.');
    }
    playCalls.add(_loadedPath ?? 'no-path');
    _isPlaying = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls.add(_loadedPath ?? 'no-path');
    _isPlaying = false;
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls.add(position);
    _position = position;
  }

  @override
  void updateSpectrumSettings(SpectrumSettings settings) {
    // No-op for mock
  }

  @override
  void setCaptureEnabled(bool enabled) {
    // No-op for mock
  }

  @override
  void suspendTimers() {
    suspendTimerCalls += 1;
  }

  @override
  void resumeTimers() {
    resumeTimerCalls += 1;
  }

  // Test helpers

  /// Simulate track ending naturally
  void emitTrackEnded() {
    _eventController.add(TransportEndedEvent(path: _loadedPath));
    _isPlaying = false;
  }

  /// Simulate an error during playback
  void emitError(String path, Object error) {
    _eventController.add(TransportErrorEvent(path: path, error: error));
  }

  /// Simulate position update
  void emitPosition(Duration position) {
    _position = position;
    _eventController.add(TransportPositionEvent(position: position));
  }

  /// Set the duration for the currently loaded track
  void setDuration(Duration duration) {
    _duration = duration;
  }

  /// Get current playing state
  bool get isPlaying => _isPlaying;

  /// Get the currently loaded path
  String? get loadedPath => _loadedPath;

  /// Reset all call tracking
  void resetCalls() {
    loadCalls.clear();
    preloadCalls.clear();
    playCalls.clear();
    pauseCalls.clear();
    seekCalls.clear();
    suspendTimerCalls = 0;
    resumeTimerCalls = 0;
    positionReadCount = 0;
    durationReadCount = 0;
  }
}
