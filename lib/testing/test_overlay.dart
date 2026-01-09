import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../providers/audio_player_provider.dart';
import 'playback_diagnostics.dart';
import 'test_harness.dart';

class TestKeys {
  static const dump = ValueKey<String>('test.dump');
  static const emitEnded = ValueKey<String>('test.emitEnded');
  static const prev = ValueKey<String>('test.prev');
  static const playPause = ValueKey<String>('test.playPause');
  static const next = ValueKey<String>('test.next');

  static ValueKey<String> queueItem(int index) =>
      ValueKey<String>('test.queueItem.$index');
}

/// Small always-on overlay for emulator automation.
///
/// This is only used from `main_test.dart` and is not part of the production app.
class TestOverlay extends StatelessWidget {
  const TestOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerProvider>();

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.black.withAlpha(200),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 220,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'TEST PANEL',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        key: TestKeys.dump,
                        onPressed: () {
                          final c = TestHarness.instance.controller;
                          if (c != null) {
                            PlaybackDiagnostics.dumpToLogcat(c);
                          }
                        },
                        icon: const Icon(
                          Icons.bug_report,
                          color: Colors.white70,
                        ),
                        tooltip: 'Dump diagnostics to logcat',
                      ),
                      IconButton(
                        key: TestKeys.emitEnded,
                        onPressed: TestHarness.instance.emitEnded,
                        icon: const Icon(
                          Icons.stop_circle,
                          color: Colors.white70,
                        ),
                        tooltip: 'Emit ended event',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      IconButton(
                        key: TestKeys.prev,
                        onPressed: player.previous,
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        key: TestKeys.playPause,
                        onPressed: player.playPause,
                        icon: Icon(
                          player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        key: TestKeys.next,
                        onPressed: player.next,
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'idx=${player.currentIndex ?? '-'} playing=${player.isPlaying}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: _QueueList(
                    queue: player.queue,
                    currentIndex: player.currentIndex,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  final List<AudioTrack> queue;
  final int? currentIndex;

  const _QueueList({required this.queue, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final player = context.read<AudioPlayerProvider>();
    return ListView.builder(
      itemCount: queue.length,
      itemBuilder: (context, index) {
        final t = queue[index];
        final isActive = currentIndex == index;
        final isNotFound = t.isNotFound;
        final title = isNotFound ? '(Not found) ${t.title}' : t.title;
        return ListTile(
          key: TestKeys.queueItem(index),
          dense: true,
          leading: Icon(
            isNotFound
                ? Icons.error
                : (isActive ? Icons.play_arrow_rounded : Icons.music_note),
            color: isNotFound
                ? Colors.redAccent
                : (isActive ? const Color(0xFF00FF88) : Colors.white54),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          onTap: () => player.playFromQueueIndex(index),
        );
      },
    );
  }
}
