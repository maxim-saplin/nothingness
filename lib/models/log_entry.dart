class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.level = LogLevel.info,
  });

  final DateTime timestamp;
  final String tag;
  final String message;
  final LogLevel level;
}

enum LogLevel { info, warning, error }
