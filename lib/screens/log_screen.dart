import 'package:flutter/material.dart';

import '../models/log_entry.dart';
import '../services/logging_service.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Colors.white70;
      case LogLevel.warning:
        return Colors.amberAccent;
      case LogLevel.error:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logging = LoggingService();
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E14),
        elevation: 0,
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Clear logs',
            onPressed: logging.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<LogEntry>>(
        valueListenable: logging.logsNotifier,
        builder: (context, entries, _) {
          if (entries.isEmpty) {
            return const Center(
              child: Text(
                'No logs yet',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return Scrollbar(
            thumbVisibility: true,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemBuilder: (context, index) {
                final entry =
                    entries[entries.length - 1 - index]; // newest first
                final ts = entry.timestamp.toLocal();
                final timeLabel =
                    '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
                return SelectableText.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '[$timeLabel] ',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      TextSpan(
                        text: '[${entry.tag}] ',
                        style: TextStyle(
                          color: _levelColor(entry.level),
                          fontSize: 12,
                        ),
                      ),
                      TextSpan(
                        text: entry.message,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              },
              separatorBuilder: (context, index) =>
                  const Divider(color: Colors.white12, height: 12),
              itemCount: entries.length,
            ),
          );
        },
      ),
    );
  }
}
