import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/playback_controller.dart';

/// Emits a structured, grep-friendly diagnostic line to logcat / debug console.
///
/// Format: `NOTHING_DIAG|<tag>|<json>`
class PlaybackDiagnostics {
  static void dumpToLogcat(
    PlaybackController controller, {
    String tag = 'playback',
  }) {
    final payload = controller.diagnosticsSnapshot();
    final json = jsonEncode(payload);
    debugPrint('NOTHING_DIAG|$tag|$json');
  }
}
