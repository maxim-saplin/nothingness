import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/audio_track.dart';
import 'metadata_extractor.dart';

/// Lightweight representation of a media item path and title.
class LibrarySong {
  const LibrarySong({required this.path, required this.title});

  final String path;
  final String title;
}

/// Represents a folder entry in the library view.
class LibraryFolder {
  const LibraryFolder({required this.path, required this.name});

  final String path;
  final String name;
}

/// Result of a folder load operation.
class LibraryListing {
  const LibraryListing({
    required this.path,
    required this.folders,
    required this.tracks,
  });

  final String path;
  final List<LibraryFolder> folders;
  final List<AudioTrack> tracks;
}

/// Encapsulates logic for resolving library folders and tracks across platforms.
class LibraryBrowser {
  LibraryBrowser({required this.supportedExtensions});

  final Set<String> supportedExtensions;

  /// Builds a virtual folder listing from a flat list of songs (MediaStore).
  Future<LibraryListing> buildVirtualListing({
    required String basePath,
    required List<LibrarySong> songs,
  }) async {
    final normalizedBase = _normalizePath(basePath);
    final folderPaths = <String>{};
    final folders = <LibraryFolder>[];
    final tracks = <AudioTrack>[];

    final extractor = createMetadataExtractor();

    for (final song in songs) {
      if (!song.path.startsWith(normalizedBase)) continue;

      var relative = song.path.substring(normalizedBase.length);
      if (relative.startsWith('/')) {
        relative = relative.substring(1);
      }
      if (relative.isEmpty) continue;

      final parts = relative.split('/');
      if (parts.length == 1) {
        // Direct child file
        if (_isSupported(song.path)) {
          try {
            // Extract metadata to get artist, but prefer title from LibrarySong
            final extracted = await extractor.extractMetadata(song.path);
            tracks.add(AudioTrack(
              path: song.path,
              title: song.title.isNotEmpty ? song.title : extracted.title,
              artist: extracted.artist,
            ));
          } catch (e) {
            // Fallback to song title if extraction fails
            tracks.add(AudioTrack(path: song.path, title: song.title));
          }
        }
      } else {
        // Child folder
        final childName = parts.first;
        final childPath = p.join(normalizedBase, childName);
        if (!folderPaths.contains(childPath)) {
          folderPaths.add(childPath);
          folders.add(LibraryFolder(path: childPath, name: childName));
        }
      }
    }

    folders.sort((a, b) => a.path.compareTo(b.path));
    tracks.sort((a, b) => a.title.compareTo(b.title));

    return LibraryListing(path: normalizedBase, folders: folders, tracks: tracks);
  }

  /// Lists a folder directly from the file system (used on macOS and tests).
  Future<LibraryListing> listFileSystem(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw Exception('Folder does not exist');
    }

    final folders = <LibraryFolder>[];
    final tracks = <AudioTrack>[];

    final extractor = createMetadataExtractor();

    await for (final entity in directory.list()) {
      if (entity is Directory) {
        if (!p.basename(entity.path).startsWith('.')) {
          folders.add(
            LibraryFolder(path: entity.path, name: p.basename(entity.path)),
          );
        }
      } else if (entity is File) {
        if (_isSupported(entity.path)) {
          try {
            final track = await extractor.extractMetadata(entity.path);
            tracks.add(track);
          } catch (e) {
            // Fallback to filename if extraction fails
            tracks.add(
              AudioTrack(
                path: entity.path,
                title: p.basenameWithoutExtension(entity.path),
              ),
            );
          }
        }
      }
    }

    folders.sort((a, b) => a.path.compareTo(b.path));
    tracks.sort((a, b) => a.title.compareTo(b.title));

    return LibraryListing(path: path, folders: folders, tracks: tracks);
  }

  bool _isSupported(String filePath) {
    final ext = p.extension(filePath).replaceAll('.', '').toLowerCase();
    return supportedExtensions.contains(ext);
  }

  String _normalizePath(String path) => path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}
