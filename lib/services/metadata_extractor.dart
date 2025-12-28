import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

import '../models/audio_track.dart';
import '../models/supported_extensions.dart';
import 'settings_service.dart';

/// Abstract interface for metadata extraction strategies.
abstract class MetadataExtractor {
  /// Extracts metadata from a file path and returns an AudioTrack.
  Future<AudioTrack> extractMetadata(String filePath);
}

/// Android implementation using on_audio_query to query MediaStore.
class AndroidMetadataExtractor implements MetadataExtractor {
  final OnAudioQuery _audioQuery;
  final bool useFilenameOverride;

  AndroidMetadataExtractor({
    OnAudioQuery? audioQuery,
    this.useFilenameOverride = false,
  }) : _audioQuery = audioQuery ?? OnAudioQuery();

  @override
  Future<AudioTrack> extractMetadata(String filePath) async {
    // If override is enabled, skip MediaStore and use filename parsing directly
    if (useFilenameOverride) {
      return _parseFilenameMetadata(filePath);
    }

    try {
      // Query MediaStore for songs matching the file path
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      // Find the song matching the file path
      final matchingSong = songs.firstWhere(
        (song) => song.data == filePath,
        orElse: () => throw StateError('No matching song found'),
      );

      // Extract metadata from MediaStore
      final title = matchingSong.title.isNotEmpty
          ? matchingSong.title
          : _parseFilenameMetadata(filePath).title;
      final artist = matchingSong.artist?.isNotEmpty == true
          ? matchingSong.artist!
          : _parseFilenameMetadata(filePath).artist;

      return AudioTrack(path: filePath, title: title, artist: artist);
    } catch (e) {
      debugPrint(
        '[AndroidMetadataExtractor] MediaStore query failed for $filePath: $e',
      );
      // Fallback to filename parsing
      return _parseFilenameMetadata(filePath);
    }
  }

  /// Filename parsing fallback utility.
  AudioTrack _parseFilenameMetadata(String filePath) {
    // Split filename before removing extensions to preserve extensions in title
    final fullBasename = p.basename(filePath);
    final parts = _splitFilename(fullBasename);

    return AudioTrack(
      path: filePath,
      title: parts['title'] ?? fullBasename,
      artist: parts['artist'] ?? '',
    );
  }

  Map<String, String> _splitFilename(String basename) {
    // Find first occurrence of separator from left: '-', '−', or '—'
    final dashIndex = basename.indexOf('-');
    final minusIndex = basename.indexOf('−');
    final emDashIndex = basename.indexOf('—');

    int? separatorIndex;
    if (dashIndex >= 0) {
      separatorIndex = dashIndex;
    } else if (minusIndex >= 0) {
      separatorIndex = minusIndex;
    } else if (emDashIndex >= 0) {
      separatorIndex = emDashIndex;
    }

    if (separatorIndex == null) {
      // No separator found: remove extensions and use as title
      var titleBasename = basename;
      while (titleBasename.contains('.') &&
          titleBasename != p.basenameWithoutExtension(titleBasename)) {
        titleBasename = p.basenameWithoutExtension(titleBasename);
      }
      return {'title': titleBasename, 'artist': ''};
    }

    final artistPart = basename.substring(0, separatorIndex);
    final artist = artistPart.trim();
    var titlePart = basename.substring(separatorIndex + 1);

    // Check if title part is empty or only contains extension
    var titleTrimmed = titlePart.trim();
    final standardExtensions = SupportedExtensions.supportedExtensionsWithDots;
    final isOnlyExtension =
        titleTrimmed.isEmpty ||
        (titleTrimmed.startsWith('.') &&
            standardExtensions.contains(titleTrimmed.toLowerCase()));

    if (isOnlyExtension) {
      // Check if artist part ends with space and separator is dash (e.g., "Artist -" in "Artist -.mp3")
      final separatorChar = basename[separatorIndex];
      final artistEndsWithSpaceDash =
          artistPart.endsWith(' ') &&
          (separatorChar == '-' ||
              separatorChar == '−' ||
              separatorChar == '—');

      // If artist ends with space and separator is dash, use basename without extension as title
      // (e.g., "Artist -.mp3" -> title "Artist -")
      if (artistEndsWithSpaceDash) {
        var titleBasename = basename;
        while (titleBasename.contains('.') &&
            titleBasename != p.basenameWithoutExtension(titleBasename)) {
          titleBasename = p.basenameWithoutExtension(titleBasename);
        }
        return {'title': titleBasename, 'artist': artist};
      }

      // If separator is at the very end or immediately followed by extension,
      // return empty title (e.g., "Artist-" or "Artist-.mp3" -> empty title)
      if (separatorIndex + 1 >= basename.length ||
          titleTrimmed.startsWith('.')) {
        return {'title': '', 'artist': artist};
      }

      // Fallback: use basename without extension
      var titleBasename = basename;
      while (titleBasename.contains('.') &&
          titleBasename != p.basenameWithoutExtension(titleBasename)) {
        titleBasename = p.basenameWithoutExtension(titleBasename);
      }
      return {'title': titleBasename, 'artist': artist};
    }

    // Remove standard audio extensions from title, but preserve multiple extensions
    // Check if title ends with a standard audio extension
    var title = titleTrimmed;
    final lastDotIndex = title.lastIndexOf('.');
    if (lastDotIndex > 0) {
      final lastExtension = title.substring(lastDotIndex).toLowerCase();
      // If it's a standard extension and there's only one extension, remove it
      if (standardExtensions.contains(lastExtension) &&
          !title.substring(0, lastDotIndex).contains('.')) {
        title = title.substring(0, lastDotIndex).trim();
      } else {
        // Multiple extensions - keep them but trim whitespace
        title = title.trim();
      }
    } else {
      title = title.trim();
    }

    return {'title': title, 'artist': artist};
  }
}

/// macOS implementation using filename parsing (extensible for future metadata library).
class MacOSMetadataExtractor implements MetadataExtractor {
  @override
  Future<AudioTrack> extractMetadata(String filePath) async {
    // Use filename parsing only (extensible design allows future metadata library integration)
    return _parseFilenameMetadata(filePath);
  }

  /// Filename parsing utility.
  AudioTrack _parseFilenameMetadata(String filePath) {
    // Split filename before removing extensions to preserve extensions in title
    final fullBasename = p.basename(filePath);
    final parts = _splitFilename(fullBasename);

    return AudioTrack(
      path: filePath,
      title: parts['title'] ?? fullBasename,
      artist: parts['artist'] ?? '',
    );
  }

  Map<String, String> _splitFilename(String basename) {
    // Find first occurrence of separator from left: '-', '−', or '—'
    final dashIndex = basename.indexOf('-');
    final minusIndex = basename.indexOf('−');
    final emDashIndex = basename.indexOf('—');

    int? separatorIndex;
    if (dashIndex >= 0) {
      separatorIndex = dashIndex;
    } else if (minusIndex >= 0) {
      separatorIndex = minusIndex;
    } else if (emDashIndex >= 0) {
      separatorIndex = emDashIndex;
    }

    if (separatorIndex == null) {
      // No separator found: remove extensions and use as title
      var titleBasename = basename;
      while (titleBasename.contains('.') &&
          titleBasename != p.basenameWithoutExtension(titleBasename)) {
        titleBasename = p.basenameWithoutExtension(titleBasename);
      }
      return {'title': titleBasename, 'artist': ''};
    }

    final artistPart = basename.substring(0, separatorIndex);
    final artist = artistPart.trim();
    var titlePart = basename.substring(separatorIndex + 1);

    // Check if title part is empty or only contains extension
    var titleTrimmed = titlePart.trim();
    final standardExtensions = SupportedExtensions.supportedExtensionsWithDots;
    final isOnlyExtension =
        titleTrimmed.isEmpty ||
        (titleTrimmed.startsWith('.') &&
            standardExtensions.contains(titleTrimmed.toLowerCase()));

    if (isOnlyExtension) {
      // Check if artist part ends with space and separator is dash (e.g., "Artist -" in "Artist -.mp3")
      final separatorChar = basename[separatorIndex];
      final artistEndsWithSpaceDash =
          artistPart.endsWith(' ') &&
          (separatorChar == '-' ||
              separatorChar == '−' ||
              separatorChar == '—');

      // If artist ends with space and separator is dash, use basename without extension as title
      // (e.g., "Artist -.mp3" -> title "Artist -")
      if (artistEndsWithSpaceDash) {
        var titleBasename = basename;
        while (titleBasename.contains('.') &&
            titleBasename != p.basenameWithoutExtension(titleBasename)) {
          titleBasename = p.basenameWithoutExtension(titleBasename);
        }
        return {'title': titleBasename, 'artist': artist};
      }

      // If separator is at the very end or immediately followed by extension,
      // return empty title (e.g., "Artist-" or "Artist-.mp3" -> empty title)
      if (separatorIndex + 1 >= basename.length ||
          titleTrimmed.startsWith('.')) {
        return {'title': '', 'artist': artist};
      }

      // Fallback: use basename without extension
      var titleBasename = basename;
      while (titleBasename.contains('.') &&
          titleBasename != p.basenameWithoutExtension(titleBasename)) {
        titleBasename = p.basenameWithoutExtension(titleBasename);
      }
      return {'title': titleBasename, 'artist': artist};
    }

    // Remove standard audio extensions from title, but preserve multiple extensions
    // Check if title ends with a standard audio extension
    var title = titleTrimmed;
    final lastDotIndex = title.lastIndexOf('.');
    if (lastDotIndex > 0) {
      final lastExtension = title.substring(lastDotIndex).toLowerCase();
      // If it's a standard extension and there's only one extension, remove it
      if (standardExtensions.contains(lastExtension) &&
          !title.substring(0, lastDotIndex).contains('.')) {
        title = title.substring(0, lastDotIndex).trim();
      } else {
        // Multiple extensions - keep them but trim whitespace
        title = title.trim();
      }
    } else {
      title = title.trim();
    }

    return {'title': title, 'artist': artist};
  }
}

/// Factory function to create platform-specific metadata extractor.
MetadataExtractor createMetadataExtractor() {
  if (Platform.isAndroid) {
    final useFilenameOverride =
        SettingsService().useFilenameForMetadataNotifier.value;
    return AndroidMetadataExtractor(
      useFilenameOverride: useFilenameOverride,
    );
  } else {
    return MacOSMetadataExtractor();
  }
}

/// Main function to extract metadata from a file path.
Future<AudioTrack> extractMetadata(String filePath) async {
  final extractor = createMetadataExtractor();
  return await extractor.extractMetadata(filePath);
}
