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

  const TransportErrorEvent({required this.path, required this.error});
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

/// Thin abstraction over platform-specific players (just_audio, SoLoud): file
/// load, play/pause/seek, position/duration, and event emission. No queue,
/// skip-on-error, or user-intent logic — that lives in PlaybackController.
abstract class AudioTransport {
  Stream<TransportEvent> get eventStream;

  Future<Duration> get position;

  /// Duration of currently loaded track, or Duration.zero if none.
  Future<Duration> get duration;

  Future<void> init();

  Future<void> dispose();

  /// Emits TransportLoadedEvent on success, TransportErrorEvent on failure.
  Future<void> load(String path, {String? title, String? artist});

  /// Best-effort gapless look-ahead (B-037): makes the next [load] of the same
  /// path a near-instant source swap. May no-op; a failed preload must not
  /// surface an error — the eventual [load] is the authoritative attempt.
  Future<void> preload(String path) async {}

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// Spectrum data (optional — may be empty if not supported).
  Stream<List<double>> get spectrumStream;

  void updateSpectrumSettings(SpectrumSettings settings);

  void setCaptureEnabled(bool enabled);

  /// Suspend periodic timers to save battery while backgrounded.
  void suspendTimers() {}

  /// Resume periodic timers when returning to foreground.
  void resumeTimers() {}
}
