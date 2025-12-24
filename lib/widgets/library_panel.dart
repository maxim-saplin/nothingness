import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/audio_player_service.dart';

class LibraryPanel extends StatefulWidget {
  final AudioPlayerService audioPlayerService;
  final VoidCallback onClose;

  const LibraryPanel({
    super.key,
    required this.audioPlayerService,
    required this.onClose,
  });

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel>
    with SingleTickerProviderStateMixin {
  String? _currentPath;
  bool _loading = false;
  String? _error;
  List<Directory> _dirs = [];
  List<AudioTrack> _files = [];

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
        child: DefaultTabController(
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
                    _buildFolders(),
                  ],
                ),
              ),
            ],
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
          ValueListenableBuilder<int?>(
            valueListenable: widget.audioPlayerService.currentIndexNotifier,
            builder: (context, current, _) {
              return ValueListenableBuilder<List<AudioTrack>>(
                valueListenable: widget.audioPlayerService.queueNotifier,
                builder: (context, queue, child) {
                  if (queue.isEmpty) {
                    return _emptyState('Queue is empty',
                        'Pick a folder and tap Play All');
                  }
                  return Expanded(
                    child: ListView.separated(
                      itemBuilder: (context, index) {
                        final track = queue[index];
                        final isActive = current == index;
                        return ListTile(
                          leading: Icon(
                            isActive
                                ? Icons.play_arrow_rounded
                                : Icons.music_note,
                            color: isActive
                                ? const Color(0xFF00FF88)
                                : Colors.white70,
                          ),
                          title: Text(
                            track.title,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white70,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          onTap: () async {
                            await widget.audioPlayerService
                                .setQueue(queue, startIndex: index);
                          },
                        );
                      },
                        separatorBuilder: (context, separatorIndex) =>
                          Divider(color: Colors.white12, height: 1),
                      itemCount: queue.length,
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),

        ],
      ),
    );
  }

  Widget _buildFolders() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Pick Folder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF88),
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(width: 10),
              if (_currentPath != null)
                TextButton.icon(
                  onPressed: _playAll,
                  icon: const Icon(Icons.queue_music_rounded,
                      color: Color(0xFF00FF88)),
                  label: const Text(
                    'Play All',
                    style: TextStyle(color: Color(0xFF00FF88)),
                  ),
                ),
              const Spacer(),
              if (_currentPath != null)
                IconButton(
                  onPressed: _navigateUp,
                  icon: const Icon(Icons.arrow_upward, color: Colors.white70),
                  tooltip: 'Up',
                ),
            ],
          ),
          if (_currentPath != null) ...[
            const SizedBox(height: 6),
            Text(
              _currentPath!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)),
            )
          else if (_error != null)
            _emptyState('Cannot open folder', _error!)
          else if (_currentPath == null)
            _emptyState('No folder selected', 'Pick a folder to browse audio')
          else if (_dirs.isEmpty && _files.isEmpty)
            _emptyState('Empty folder', 'No audio files found here')
          else
            Expanded(
              child: ListView(
                children: [
                  ..._dirs.map(_buildDirectoryTile),
                  ..._files.map(_buildFileTile),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectoryTile(Directory dir) {
    return ListTile(
      leading: const Icon(Icons.folder, color: Colors.amber),
      title: Text(
        p.basename(dir.path),
        style: const TextStyle(color: Colors.white),
      ),
      onTap: () => _loadFolder(dir.path),
    );
  }

  Widget _buildFileTile(AudioTrack track) {
    final index = _files.indexOf(track);
    return ListTile(
      leading: const Icon(Icons.audio_file_rounded, color: Colors.white70),
      title: Text(
        track.title,
        style: const TextStyle(color: Colors.white70),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        await widget.audioPlayerService.setQueue(_files, startIndex: index);
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

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    await _loadFolder(path);
  }

  Future<void> _loadFolder(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dirs = <Directory>[];
      final files = <AudioTrack>[];
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw Exception('Folder does not exist');
      }

      final supported = <String>{'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'};
      await for (final entity in directory.list()) {
        if (entity is Directory) {
          dirs.add(entity);
        } else if (entity is File) {
          final ext = p.extension(entity.path).replaceAll('.', '').toLowerCase();
          if (supported.contains(ext)) {
            files.add(
              AudioTrack(
                path: entity.path,
                title: p.basenameWithoutExtension(entity.path),
              ),
            );
          }
        }
      }

      dirs.sort((a, b) => a.path.compareTo(b.path));
      files.sort((a, b) => a.title.compareTo(b.title));

      setState(() {
        _currentPath = path;
        _dirs = dirs;
        _files = files;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _navigateUp() async {
    if (_currentPath == null) return;
    final parent = Directory(_currentPath!).parent.path;
    await _loadFolder(parent);
  }

  Future<void> _playAll() async {
    if (_currentPath == null) return;
    setState(() {
      _loading = true;
    });
    try {
      final tracks = await widget.audioPlayerService.scanFolder(_currentPath!);
      if (tracks.isNotEmpty) {
        await widget.audioPlayerService.setQueue(tracks, startIndex: 0);
        widget.onClose();
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }
}
