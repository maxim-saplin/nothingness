import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Telemetry/diagnostics collaborator extracted from `PlaybackController`
/// (SRP). Owns the recent-log + audio-event ring buffers and mirrors both onto
/// the `nothingness.playback` [Logger]. The string/format CONTRACT here is
/// asserted by tests + the QA harness — keep it byte-identical.
class PlaybackTelemetry {
  PlaybackTelemetry({
    this.captureRecentLogs = false,
    this.recentLogCapacity = 50,
    this.debugPlaybackLogs = false,
  });

  final bool captureRecentLogs;
  final int recentLogCapacity;
  final bool debugPlaybackLogs;

  static final Logger _logger = Logger('nothingness.playback');

  final List<String> _recentLogs = <String>[];
  final List<String> _audioEvents = <String>[];
  static const int _audioEventsCap = 300;

  static void _appendCapped(List<String> buffer, String entry, int cap) {
    buffer.add(entry);
    if (buffer.length > cap) buffer.removeRange(0, buffer.length - cap);
  }

  /// Append a free-form controller log to the recent-logs ring (capped, only
  /// when capture is enabled) and mirror it onto the logger.
  void log(String message) {
    if (captureRecentLogs || debugPlaybackLogs) {
      _appendCapped(_recentLogs, message, max(1, recentLogCapacity));
    }
    if (debugPlaybackLogs) debugPrint('[PlaybackController] $message');
    _logger.fine(message);
  }

  /// Append a structured audio event (`$ts $tag$dataStr`) to the audio-events
  /// ring (cap 300) and mirror it onto the logger.
  void event(String tag, [Map<String, Object?>? data]) {
    final ts = DateTime.now().toIso8601String();
    final dataStr = (data == null || data.isEmpty)
        ? ''
        : ' ${data.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    final entry = '$ts $tag$dataStr';
    _appendCapped(_audioEvents, entry, _audioEventsCap);
    _logger.fine(entry);
  }

  /// Recent controller logs (if enabled), for test/diagnostics.
  List<String> get recentLogs => List<String>.unmodifiable(_recentLogs);

  /// Audio-event ring buffer (interruption / route / load / error).
  List<String> get audioEvents => List<String>.unmodifiable(_audioEvents);
}
