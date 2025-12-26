import 'dart:async';

import '../models/spectrum_settings.dart';

/// Events emitted by AudioTransport to notify about state changes.
sealed class TransportEvent {
  const TransportEvent();
}

/// Emitted when a track fails to load or play.
class TransportErrorEvent extends TransportEvent {
  final String? path;
  final Object error;

  const TransportErrorEvent({
    required this.path,
    required this.error,
  });
}

/// Emitted when a track finishes playing naturally.
class TransportEndedEvent extends TransportEvent {
  final String? path;

  const TransportEndedEvent({required this.path});
}

/// Emitted when a track successfully loads.
class TransportLoadedEvent extends TransportEvent {
  final String? path;

  const TransportLoadedEvent({required this.path});
}

/// Emitted periodically with position updates.
class TransportPositionEvent extends TransportEvent {
  final Duration position;

  const TransportPositionEvent({required this.position});
}

/// Minimal interface for controlling a native audio player.
/// This is a thin abstraction over platform-specific players (just_audio, SoLoud).
/// 
/// Responsibilities:
/// - Loading audio files
/// - Play/pause/seek control
/// - Position and duration queries
/// - Emitting events (error, ended, loaded, position)
/// 
/// Does NOT handle:
/// - Queue management
/// - Skip-on-error logic
/// - User intent tracking
abstract class AudioTransport {
  /// Stream of transport events (errors, track ended, loaded, position).
  Stream<TransportEvent> get eventStream;

  /// Current playback position.
  Future<Duration> get position;

  /// Duration of currently loaded track, or Duration.zero if none.
  Future<Duration> get duration;

  /// Initialize the transport.
  Future<void> init();

  /// Dispose resources.
  Future<void> dispose();

  /// Load an audio file from the given path.
  /// Emits TransportLoadedEvent on success, TransportErrorEvent on failure.
  Future<void> load(String path, {String? title, String? artist});

  /// Start playback.
  Future<void> play();

  /// Pause playback.
  Future<void> pause();

  /// Seek to the given position.
  Future<void> seek(Duration position);

  /// Stream of spectrum data (optional - may be empty if not supported).
  Stream<List<double>> get spectrumStream;

  /// Update spectrum settings.
  void updateSpectrumSettings(SpectrumSettings settings);

  /// Enable or disable spectrum capture.
  void setCaptureEnabled(bool enabled);
}

