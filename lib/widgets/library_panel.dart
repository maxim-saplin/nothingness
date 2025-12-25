import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../controllers/library_controller.dart';
import '../models/audio_track.dart';
import '../providers/audio_player_provider.dart';
import '../services/library_browser.dart';
import '../services/library_service.dart';

class LibraryPanel extends StatefulWidget {
  const LibraryPanel({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  late final LibraryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LibraryController(
      libraryBrowser:
          LibraryBrowser(supportedExtensions: AudioPlayerProvider.supportedExtensions),
      libraryService: LibraryService(),
    )..init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E14).withAlpha(240),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          border: Border.all(color: Colors.white.withAlpha(16)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 12,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: ChangeNotifierProvider<LibraryController>.value(
          value: _controller,
          child: Consumer<LibraryController>(
            builder: (context, controller, _) {
              if (Platform.isAndroid && !controller.hasPermission) {
                return Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                size: 48,
                                color: Colors.white54,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Permissions Required',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'To browse your music library and visualize audio, Nothingness needs access to:\n\n'
                                '• Storage: To read audio files\n'
                                '• Microphone: To generate the spectrum visualization',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: controller.requestPermission,
                                icon: const Icon(Icons.check),
                                label: const Text('Grant Permissions'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00FF88),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                              if (controller.error != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  controller.error!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    _buildHeader(),
                    const TabBar(
                      indicatorColor: Color(0xFF00FF88),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      tabs: [
                        Tab(text: 'Now Playing'),
                        Tab(text: 'Folders'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildNowPlaying(),
                          ValueListenableBuilder<Map<String, String>>(
                            valueListenable: LibraryService().rootsNotifier,
                            builder: (context, roots, _) {
                              return _buildFolders(context, roots);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlaying() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Consumer<AudioPlayerProvider>(
            builder: (context, player, _) {
              final queue = player.queue;
              final current = player.currentIndex;
              return Row(
                children: [
                  FilledButton.icon(
                    onPressed: queue.isEmpty
                        ? null
                        : () => player.shuffleQueue(),
                    icon: const Icon(Icons.shuffle_rounded),
                    label: Text(player.shuffle ? 'Shuffle (on)' : 'Shuffle'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          player.shuffle ? const Color(0xFF00FF88) : Colors.white12,
                      foregroundColor: player.shuffle ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: queue.isEmpty
                        ? null
                        : () => player.disableShuffle(),
                    icon: const Icon(
                      Icons.format_list_numbered_rtl,
                      color: Color(0xFF00FF88),
                    ),
                    label: const Text(
                      'Reset order',
                      style: TextStyle(color: Color(0xFF00FF88)),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(current ?? -1) + 1} / ${queue.length}',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Consumer<AudioPlayerProvider>(
            builder: (context, player, _) {
              final queue = player.queue;
              final current = player.currentIndex;
              if (queue.isEmpty) {
                return _emptyState('Queue is empty', 'Pick a folder and tap Play All');
              }
              return Expanded(
                child: ListView.separated(
                  itemBuilder: (context, index) {
                    final track = queue[index];
                    final isActive = current == index;
                    return ListTile(
                      leading: Icon(
                        isActive
                            ? (player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded)
                            : Icons.music_note,
                        color: isActive ? const Color(0xFF00FF88) : Colors.white70,
                      ),
                      title: Text(
                        track.title,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      onTap: () async {
                        if (isActive) {
                          await player.playPause();
                        } else {
                          await player.playFromQueueIndex(index);
                        }
                      },
                    );
                  },
                  separatorBuilder: (context, separatorIndex) =>
                      const Divider(color: Colors.white12, height: 1),
                  itemCount: queue.length,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildFolders(BuildContext context, Map<String, String> roots) {
    final controller = context.watch<LibraryController>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (Platform.isMacOS) ...[
                ElevatedButton.icon(
                  onPressed: () => _pickFolder(context),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Add Folder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF88),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ] else
                const SizedBox(width: 10),
              if (controller.currentPath != null)
                TextButton.icon(
                  onPressed: () => _playAll(context),
                  icon: const Icon(Icons.queue_music_rounded, color: Color(0xFF00FF88)),
                  label: const Text(
                    'Play All',
                    style: TextStyle(color: Color(0xFF00FF88)),
                  ),
                ),
              const Spacer(),
              if (controller.currentPath != null)
                IconButton(
                  onPressed: controller.navigateUp,
                  icon: const Icon(Icons.arrow_upward, color: Colors.white70),
                  tooltip: 'Up',
                ),
            ],
          ),
          if (controller.currentPath != null) ...[
            const SizedBox(height: 6),
            Text(
              controller.currentPath!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          if (controller.isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)),
            )
          else if (controller.error != null)
            _emptyState('Cannot open folder', controller.error!)
          else if (controller.currentPath == null)
            roots.isEmpty && !Platform.isAndroid
                ? _emptyState('No library folders', 'Add a folder to start browsing')
                : Expanded(
                    child: ListView(
                      children: roots.keys.map(_buildRootTile).toList(),
                    ),
                  )
          else if (controller.folders.isEmpty && controller.tracks.isEmpty)
            _emptyState('Empty folder', 'No audio files found here')
          else
            Expanded(
              child: ListView(
                children: [
                  ...controller.folders.map(_buildFolderTile),
                  ...controller.tracks.map((t) => _buildFileTile(context, t)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRootTile(String path) {
    return ListTile(
      leading: const Icon(Icons.folder_special, color: Color(0xFF00FF88)),
      title: Text(
        p.basename(path),
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        path,
        style: const TextStyle(color: Colors.white38, fontSize: 10),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, color: Colors.white38),
        onPressed: () => LibraryService().removeRoot(path),
      ),
      onTap: () => _controller.loadFolder(path),
    );
  }

  Widget _buildFolderTile(LibraryFolder folder) {
    return ListTile(
      leading: const Icon(Icons.folder, color: Colors.amber),
      title: Text(
        folder.name,
        style: const TextStyle(color: Colors.white),
      ),
      onTap: () => _controller.loadFolder(folder.path),
    );
  }

  Widget _buildFileTile(BuildContext context, AudioTrack track) {
    final controller = context.read<LibraryController>();
    final index = controller.tracks.indexOf(track);
    return ListTile(
      leading: const Icon(Icons.audio_file_rounded, color: Colors.white70),
      title: Text(
        track.title,
        style: const TextStyle(color: Colors.white70),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        final player = context.read<AudioPlayerProvider>();
        await player.setQueue(
          controller.tracks,
          startIndex: index,
          shuffle: player.shuffle,
        );
        widget.onClose();
      },
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white38),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFolder(BuildContext context) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;

    await LibraryService().addRoot(path);
    await _controller.loadFolder(path);
  }

  Future<void> _playAll(BuildContext context) async {
    final controller = context.read<LibraryController>();
    final currentPath = controller.currentPath;
    if (currentPath == null) return;

    final player = context.read<AudioPlayerProvider>();
    List<AudioTrack> tracks = [];

    if (Platform.isAndroid) {
      tracks = await controller.tracksForCurrentPath();
    } else {
      tracks = await player.scanFolder(currentPath);
    }

    if (tracks.isEmpty) return;

    await player.setQueue(
      tracks,
      startIndex: 0,
      shuffle: player.shuffle,
    );
    widget.onClose();
  }
}
