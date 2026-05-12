import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/log_entry.dart';
import '../providers/audio_player_provider.dart';
import '../services/logging_service.dart';
import '../services/settings_service.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  Timer? _audioPollTimer;
  List<String> _audioEvents = const [];

  @override
  void initState() {
    super.initState();
    final settings = SettingsService();
    settings.audioDiagnosticsOverlayNotifier.addListener(_syncPolling);
    _syncPolling();
  }

  @override
  void dispose() {
    SettingsService().audioDiagnosticsOverlayNotifier.removeListener(
      _syncPolling,
    );
    _audioPollTimer?.cancel();
    super.dispose();
  }

  void _syncPolling() {
    final enabled = SettingsService().audioDiagnosticsOverlayNotifier.value;
    _audioPollTimer?.cancel();
    if (!enabled) {
      if (_audioEvents.isNotEmpty) {
        setState(() => _audioEvents = const []);
      }
      return;
    }
    _audioPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _refreshAudioEvents(),
    );
    _refreshAudioEvents();
  }

  void _refreshAudioEvents() {
    if (!mounted) return;
    final provider = context.read<AudioPlayerProvider?>();
    if (provider == null) return;
    final events = provider.audioEvents();
    if (!listEquals(events, _audioEvents)) {
      setState(() => _audioEvents = events);
    }
  }

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
    final settings = SettingsService();
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
      body: ValueListenableBuilder<bool>(
        valueListenable: settings.audioDiagnosticsOverlayNotifier,
        builder: (context, audioDiag, _) {
          return Column(
            children: [
              if (audioDiag) _audioEventsPanel(),
              Expanded(
                child: ValueListenableBuilder<List<LogEntry>>(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemBuilder: (context, index) {
                          final entry = entries[entries.length - 1 - index];
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
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _audioEventsPanel() {
    final events = _audioEvents;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: const BoxDecoration(
        color: Color(0xFF161620),
        border: Border(
          bottom: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Audio events',
                style: TextStyle(
                  color: Colors.lightGreenAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${events.length})',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: events.isEmpty
                ? const Text(
                    '(none yet)',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final line = events[events.length - 1 - index];
                        return SelectableText(
                          line,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
