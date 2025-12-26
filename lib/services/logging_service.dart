import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';

/// Simple in-memory logging service with a ValueNotifier for UI binding.
class LoggingService {
  LoggingService._internal();
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;

  // Keep a bounded list to avoid unbounded growth.
  static const int _maxEntries = 500;

  final ValueNotifier<List<LogEntry>> logsNotifier =
      ValueNotifier<List<LogEntry>>(<LogEntry>[]);

  void log({
    required String tag,
    required String message,
    LogLevel level = LogLevel.info,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      level: level,
    );

    final List<LogEntry> next = List<LogEntry>.from(logsNotifier.value)
      ..add(entry);
    if (next.length > _maxEntries) {
      next.removeRange(0, next.length - _maxEntries);
    }
    logsNotifier.value = next;

    // Preserve console visibility for developers.
    debugPrint('[$tag] $message');
  }

  void clear() {
    logsNotifier.value = <LogEntry>[];
  }
}
