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
  bool autoEmitLoadedEvent = true;
  Duration loadDelay = Duration.zero;
  
  // Call tracking for verification
  final List<String> loadCalls = [];
  final List<String> playCalls = [];
  final List<String> pauseCalls = [];
  final List<Duration> seekCalls = [];
  
  @override
  Stream<TransportEvent> get eventStream => _eventController.stream;

  @override
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  @override
  Future<Duration> get position async => _position;

  @override
  Future<Duration> get duration async => _duration;

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
  Future<void> load(String path, {String? title, String? artist}) async {
    loadCalls.add(path);
    
    if (loadDelay > Duration.zero) {
      await Future.delayed(loadDelay);
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
  Future<void> play() async {
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
    playCalls.clear();
    pauseCalls.clear();
    seekCalls.clear();
  }
}
