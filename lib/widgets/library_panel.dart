import 'dart:io';

import 'package:external_path/external_path.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../providers/audio_player_provider.dart';
import '../services/library_service.dart';

class LibraryPanel extends StatefulWidget {
  final VoidCallback onClose;

  const LibraryPanel({
    super.key,
    required this.onClose,
  });

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel>
    with SingleTickerProviderStateMixin {
  String? _currentPath;
  String? _initialAndroidRoot;
  bool _loading = false;
  String? _error;
  List<Directory> _dirs = [];
  List<AudioTrack> _files = [];
  bool _hasAllFilesPermission = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _checkAndroidPermissions();
    }
  }

  Future<void> _checkAndroidPermissions() async {
    final hasPermission = await Permission.manageExternalStorage.isGranted;
    if (!mounted) return;
    setState(() {
      _hasAllFilesPermission = hasPermission;
    });
    // If we already have permission, load the root automatically
    if (hasPermission && _currentPath == null) {
      await _loadAndroidRoot();
    }
  }

  Future<void> _loadAndroidRoot() async {
    try {
      // Get all external storage directories (internal + SD cards)
      final paths = await ExternalPath.getExternalStorageDirectories();
      if (!mounted) return;
      // ignore: unnecessary_null_comparison
      if (paths != null && paths.isNotEmpty) {
        _initialAndroidRoot = paths.first;
        // Load the first one (usually internal storage /storage/emulated/0)
        await _loadFolder(_initialAndroidRoot!);
      }
    } catch (e) {
      debugPrint('Failed to load Android root: $e');
    }
  }

  Future<void> _requestAllFilesPermission() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Request Manage External Storage for Android 11+ (API 30+)
      final status = await Permission.manageExternalStorage.request();
      if (!mounted) return;
      
      if (status.isGranted) {
        setState(() {
          _hasAllFilesPermission = true;
        });
        // Load Android root after permission is granted
        await _loadAndroidRoot();
      } else {
        setState(() {
          _error = 'All files permission is required to browse root storage';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to request permission: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
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
                    ValueListenableBuilder<Map<String, String>>(
                      valueListenable: LibraryService().rootsNotifier,
                      builder: (context, roots, _) {
                        return _buildFolders(roots);
                      },
                    ),
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
                    label:
                        Text(player.shuffle ? 'Shuffle (on)' : 'Shuffle'),
                    style: FilledButton.styleFrom(
                      backgroundColor: player.shuffle
                          ? const Color(0xFF00FF88)
                          : Colors.white12,
                      foregroundColor:
                          player.shuffle ? Colors.black : Colors.white,
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
                            ? (player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded)
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

  Widget _buildFolders(Map<String, String> roots) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (Platform.isAndroid && !_hasAllFilesPermission && _currentPath == null) ...[
                // Option 1: Request all files permission
                ElevatedButton.icon(
                  onPressed: _requestAllFilesPermission,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('All Files Permission'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF88),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                // Option 2: Use file picker (scoped storage)
                ElevatedButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Pick Folder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ] else if (Platform.isMacOS || Platform.isAndroid) ...[
                ElevatedButton.icon(
                  onPressed: _pickFolder,
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
            roots.isEmpty
                ? _emptyState(
                    'No library folders', 'Add a folder to start browsing')
                : Expanded(
                    child: ListView(
                      children: roots.keys.map(_buildRootTile).toList(),
                    ),
                  )
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
      onTap: () => _loadFolder(path),
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
        final player = context.read<AudioPlayerProvider>();
        await player.setQueue(
          _files,
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

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;

    // Persist permission
    await LibraryService().addRoot(path);

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

      final supported = AudioPlayerProvider.supportedExtensions;
      await for (final entity in directory.list()) {
        if (entity is Directory) {
          // Filter out hidden folders
          if (!p.basename(entity.path).startsWith('.')) {
            dirs.add(entity);
          }
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

      if (mounted) {
        setState(() {
          _currentPath = path;
          _dirs = dirs;
          _files = files;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _navigateUp() async {
    if (_currentPath == null) return;

    // If current path is a root or the initial Android root, go back to root list
    if (LibraryService().rootsNotifier.value.containsKey(_currentPath) ||
        (_initialAndroidRoot != null && _currentPath == _initialAndroidRoot)) {
      setState(() {
        _currentPath = null;
        _dirs = [];
        _files = [];
      });
      return;
    }

    final parent = Directory(_currentPath!).parent.path;
    await _loadFolder(parent);
  }

  Future<void> _playAll() async {
    if (_currentPath == null) return;
    setState(() {
      _loading = true;
    });
    try {
      final player = context.read<AudioPlayerProvider>();
      final tracks = await player.scanFolder(_currentPath!);
      if (!mounted) return;
      if (tracks.isNotEmpty) {
        await player.setQueue(
          tracks,
          startIndex: 0,
          shuffle: player.shuffle,
        );
        widget.onClose();
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }
}
