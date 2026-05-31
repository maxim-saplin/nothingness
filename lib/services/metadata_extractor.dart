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

  AndroidMetadataExtractor({OnAudioQuery? audioQuery, this.useFilenameOverride = false})
    : _audioQuery = audioQuery ?? OnAudioQuery();

  @override
  Future<AudioTrack> extractMetadata(String filePath) async {
    // Override skips MediaStore and parses the filename.
    if (useFilenameOverride) return _parseFilenameMetadata(filePath);

    try {
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      final song = songs.firstWhere(
        (s) => s.data == filePath,
        orElse: () => throw StateError('No matching song found'),
      );
      final artist = song.artist?.isNotEmpty == true
          ? song.artist!
          : _parseFilenameMetadata(filePath).artist;
      // Files with no ID3 title tag fall back to the filename, which can carry
      // the audio extension and an embedded "Artist - " prefix.
      final title = song.title.isNotEmpty
          ? _dropEmbeddedArtist(
              SupportedExtensions.stripFromTitle(song.title), artist)
          : _parseFilenameMetadata(filePath).title;
      return AudioTrack(path: filePath, title: title, artist: artist);
    } catch (e) {
      debugPrint('[AndroidMetadataExtractor] MediaStore query failed for $filePath: $e');
      return _parseFilenameMetadata(filePath);
    }
  }
}

/// Desktop (macOS/Linux) implementation using filename parsing.
class DesktopMetadataExtractor implements MetadataExtractor {
  @override
  Future<AudioTrack> extractMetadata(String filePath) async =>
      _parseFilenameMetadata(filePath);
}

/// Builds an [AudioTrack] from the filename's artist/title split.
///
/// B-047: the split keys on the *leftmost* separator, so a filename that
/// embeds the artist again in the title (e.g. `Artist - Artist - Song.ext`)
/// leaves the artist in the title. Apply [_dropEmbeddedArtist] — the same
/// guard the Android MediaStore path already uses — so the desktop/filename
/// path strips the redundant prefix too.
AudioTrack _parseFilenameMetadata(String filePath) {
  final base = p.basename(filePath);
  final (artist, title) = _splitFilename(base);
  return AudioTrack(
    path: filePath,
    title: title == null ? base : _dropEmbeddedArtist(title, artist),
    artist: artist,
  );
}

/// Drops a leading `"<artist> - "` the MediaStore title inherited from the
/// filename, by re-splitting it with [_splitFilename] and keeping the song only
/// when the parsed artist matches. Leaves titles that merely contain a dash
/// (e.g. "Sgt. Pepper - Reprise") untouched.
String _dropEmbeddedArtist(String title, String artist) {
  if (artist.isEmpty) return title;
  final (parsedArtist, parsedTitle) = _splitFilename(title);
  return parsedTitle != null &&
          parsedArtist.toLowerCase() == artist.toLowerCase()
      ? parsedTitle
      : title;
}

/// Strips trailing extensions repeatedly (preserves a name with no extension).
String _stripExtensions(String name) {
  var result = name;
  while (result.contains('.') && result != p.basenameWithoutExtension(result)) {
    result = p.basenameWithoutExtension(result);
  }
  return result;
}

/// Returns `(artist, title)`; a null title means "use the full basename".
(String, String?) _splitFilename(String base) {
  // First separator from the left: '-', '−' or '—'.
  final sepIndex = [base.indexOf('-'), base.indexOf('−'), base.indexOf('—')]
      .where((i) => i >= 0)
      .fold<int>(-1, (a, b) => a < 0 ? b : (b < a ? b : a));

  if (sepIndex < 0) return ('', _stripExtensions(base));

  final artistPart = base.substring(0, sepIndex);
  final artist = artistPart.trim();
  final tail = base.substring(sepIndex + 1).trim();

  final exts = SupportedExtensions.supportedExtensionsWithDots;
  final isOnlyExtension =
      tail.isEmpty || (tail.startsWith('.') && exts.contains(tail.toLowerCase()));

  if (isOnlyExtension) {
    final sep = base[sepIndex];
    // "Artist -.mp3" -> title "Artist -".
    if (artistPart.endsWith(' ') && (sep == '-' || sep == '−' || sep == '—')) {
      return (artist, _stripExtensions(base));
    }
    // Separator at end or immediately followed by an extension -> empty title.
    if (sepIndex + 1 >= base.length || tail.startsWith('.')) return (artist, '');
    return (artist, _stripExtensions(base));
  }

  // Remove a single standard audio extension; keep multiple extensions intact.
  var title = tail;
  final dot = title.lastIndexOf('.');
  if (dot > 0 &&
      exts.contains(title.substring(dot).toLowerCase()) &&
      !title.substring(0, dot).contains('.')) {
    title = title.substring(0, dot);
  }
  return (artist, title.trim());
}

/// Factory function to create platform-specific metadata extractor.
MetadataExtractor createMetadataExtractor() => Platform.isAndroid
    ? AndroidMetadataExtractor(
        useFilenameOverride: SettingsService().useFilenameForMetadataNotifier.value,
      )
    : DesktopMetadataExtractor();
