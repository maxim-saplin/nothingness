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
    // Override skips MediaStore and parses the filename.
    if (useFilenameOverride) {
      return _parseFilenameMetadata(filePath);
    }

    try {
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      final matchingSong = songs.firstWhere(
        (song) => song.data == filePath,
        orElse: () => throw StateError('No matching song found'),
      );

      // Strip any audio extension MediaStore left in the title (files with no
      // ID3 title tag fall back to the filename).
      final title = matchingSong.title.isNotEmpty
          ? SupportedExtensions.stripFromTitle(matchingSong.title)
          : _parseFilenameMetadata(filePath).title;
      final artist = matchingSong.artist?.isNotEmpty == true
          ? matchingSong.artist!
          : _parseFilenameMetadata(filePath).artist;

      return AudioTrack(path: filePath, title: title, artist: artist);
    } catch (e) {
      debugPrint(
        '[AndroidMetadataExtractor] MediaStore query failed for $filePath: $e',
      );
      return _parseFilenameMetadata(filePath);
    }
  }
}

/// Desktop (macOS/Linux) implementation using filename parsing.
class DesktopMetadataExtractor implements MetadataExtractor {
  @override
  Future<AudioTrack> extractMetadata(String filePath) async {
    return _parseFilenameMetadata(filePath);
  }
}

/// Builds an [AudioTrack] from the filename's artist/title split.
AudioTrack _parseFilenameMetadata(String filePath) {
  final fullBasename = p.basename(filePath);
  final parts = _splitFilename(fullBasename);
  return AudioTrack(
    path: filePath,
    title: parts['title'] ?? fullBasename,
    artist: parts['artist'] ?? '',
  );
}

/// Strips trailing extensions repeatedly (preserves a name with no extension).
String _stripExtensions(String basename) {
  var result = basename;
  while (result.contains('.') &&
      result != p.basenameWithoutExtension(result)) {
    result = p.basenameWithoutExtension(result);
  }
  return result;
}

Map<String, String> _splitFilename(String basename) {
  // First separator from the left: '-', '−' or '—'.
  final indices = [
    basename.indexOf('-'),
    basename.indexOf('−'),
    basename.indexOf('—'),
  ].where((i) => i >= 0);

  if (indices.isEmpty) {
    return {'title': _stripExtensions(basename), 'artist': ''};
  }
  final separatorIndex = indices.reduce((a, b) => a < b ? a : b);

  final artistPart = basename.substring(0, separatorIndex);
  final artist = artistPart.trim();
  final titleTrimmed = basename.substring(separatorIndex + 1).trim();

  final standardExtensions = SupportedExtensions.supportedExtensionsWithDots;
  final isOnlyExtension =
      titleTrimmed.isEmpty ||
      (titleTrimmed.startsWith('.') &&
          standardExtensions.contains(titleTrimmed.toLowerCase()));

  if (isOnlyExtension) {
    final separatorChar = basename[separatorIndex];
    final artistEndsWithSpaceDash =
        artistPart.endsWith(' ') &&
        (separatorChar == '-' ||
            separatorChar == '−' ||
            separatorChar == '—');

    // "Artist -.mp3" -> title "Artist -".
    if (artistEndsWithSpaceDash) {
      return {'title': _stripExtensions(basename), 'artist': artist};
    }

    // Separator at end or immediately followed by an extension -> empty title
    // (e.g. "Artist-" or "Artist-.mp3").
    if (separatorIndex + 1 >= basename.length ||
        titleTrimmed.startsWith('.')) {
      return {'title': '', 'artist': artist};
    }

    return {'title': _stripExtensions(basename), 'artist': artist};
  }

  // Remove a single standard audio extension; keep multiple extensions intact.
  var title = titleTrimmed;
  final lastDotIndex = title.lastIndexOf('.');
  if (lastDotIndex > 0) {
    final lastExtension = title.substring(lastDotIndex).toLowerCase();
    if (standardExtensions.contains(lastExtension) &&
        !title.substring(0, lastDotIndex).contains('.')) {
      title = title.substring(0, lastDotIndex).trim();
    } else {
      title = title.trim();
    }
  } else {
    title = title.trim();
  }

  return {'title': title, 'artist': artist};
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
    return DesktopMetadataExtractor();
  }
}

/// Main function to extract metadata from a file path.
Future<AudioTrack> extractMetadata(String filePath) async {
  final extractor = createMetadataExtractor();
  return await extractor.extractMetadata(filePath);
}
