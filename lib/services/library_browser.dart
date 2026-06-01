import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/audio_track.dart';
import 'metadata_extractor.dart';

/// Lightweight representation of a media item path and title.
class LibrarySong {
  const LibrarySong({required this.path, required this.title, this.artist = ''});

  final String path;
  final String title;
  // Raw MediaStore artist tag, cached from the one library scan so per-folder
  // track building never needs to re-query (avoids O(N×M)).
  final String artist;
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
    final base = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final extractor = createMetadataExtractor();
    final seenFolders = <String>{};
    final folders = <LibraryFolder>[];
    final tracks = <AudioTrack>[];

    for (final song in songs) {
      if (!song.path.startsWith(base)) continue;
      var relative = song.path.substring(base.length);
      if (relative.startsWith('/')) relative = relative.substring(1);
      if (relative.isEmpty) continue;

      final slash = relative.indexOf('/');
      if (slash < 0) {
        if (!_isSupported(song.path)) continue;
        // B-047: parse title AND artist so the `useFilenameForMetadata` setting
        // decides the source (filename vs ID3). Build from the cached scan tags
        // — NO per-song MediaStore query (was O(N×M); see buildTrackFromTags).
        tracks.add(buildTrackFromTags(
          path: song.path,
          rawTitle: song.title,
          rawArtist: song.artist,
          useFilenameOverride: extractor.useFilenameOverride,
        ));
      } else {
        final childName = relative.substring(0, slash);
        final childPath = p.join(base, childName);
        if (seenFolders.add(childPath)) {
          folders.add(LibraryFolder(path: childPath, name: childName));
        }
      }
    }

    return _sortedListing(base, folders, tracks);
  }

  /// Lists a folder directly from the file system (used on macOS and tests).
  Future<LibraryListing> listFileSystem(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) throw Exception('Folder does not exist');

    final extractor = createMetadataExtractor();
    final folders = <LibraryFolder>[];
    final tracks = <AudioTrack>[];

    await for (final entity in directory.list()) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (!name.startsWith('.')) {
          folders.add(LibraryFolder(path: entity.path, name: name));
        }
      } else if (entity is File && _isSupported(entity.path)) {
        try {
          tracks.add(await extractor.extractMetadata(entity.path));
        } catch (_) {
          tracks.add(AudioTrack(
            path: entity.path,
            title: p.basenameWithoutExtension(entity.path),
          ));
        }
      }
    }

    return _sortedListing(path, folders, tracks);
  }

  LibraryListing _sortedListing(
    String path,
    List<LibraryFolder> folders,
    List<AudioTrack> tracks,
  ) {
    folders.sort((a, b) => a.path.compareTo(b.path));
    tracks.sort((a, b) => a.title.compareTo(b.title));
    return LibraryListing(path: path, folders: folders, tracks: tracks);
  }

  bool _isSupported(String filePath) => supportedExtensions
      .contains(p.extension(filePath).replaceAll('.', '').toLowerCase());
}
