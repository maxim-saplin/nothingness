import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/metadata_extractor.dart';
import 'package:on_audio_query/on_audio_query.dart';

// Mock OnAudioQuery for testing
// Returns empty list to simulate MediaStore query failure (fallback to filename parsing)
class MockOnAudioQueryEmpty extends OnAudioQuery {
  @override
  Future<List<SongModel>> querySongs({
    SongSortType? sortType,
    OrderType? orderType,
    UriType? uriType,
    bool? ignoreCase,
    String? path,
  }) async {
    return []; // Empty list causes firstWhere to throw, triggering fallback
  }
}

void main() {
  group('MacOSMetadataExtractor', () {
    late MacOSMetadataExtractor extractor;

    setUp(() {
      extractor = MacOSMetadataExtractor();
    });

    test('parses filename with dash separator', () async {
      final track = await extractor.extractMetadata('/path/Artist - Title.mp3');
      expect(track.title, 'Title');
      expect(track.artist, 'Artist');
      expect(track.path, '/path/Artist - Title.mp3');
    });

    test('parses filename with minus separator', () async {
      final track = await extractor.extractMetadata('/path/Artist − Title.mp3');
      expect(track.title, 'Title');
      expect(track.artist, 'Artist');
    });

    test('parses filename with em-dash separator', () async {
      final track = await extractor.extractMetadata('/path/Artist — Title.mp3');
      expect(track.title, 'Title');
      expect(track.artist, 'Artist');
    });

    test('uses first separator from left when multiple exist', () async {
      final track = await extractor.extractMetadata('/path/Artist - Song - Remix.mp3');
      expect(track.title, 'Song - Remix');
      expect(track.artist, 'Artist');
    });

    test('uses entire filename as title when no separator found', () async {
      final track = await extractor.extractMetadata('/path/SongTitle.mp3');
      expect(track.title, 'SongTitle');
      expect(track.artist, '');
    });

    test('trims whitespace from artist and title', () async {
      final track = await extractor.extractMetadata('/path/  Artist  -  Title  .mp3');
      expect(track.title, 'Title');
      expect(track.artist, 'Artist');
    });

    test('handles empty title after separator', () async {
      final track = await extractor.extractMetadata('/path/Artist -.mp3');
      expect(track.title, 'Artist -');
      expect(track.artist, 'Artist');
    });

    test('handles empty artist before separator', () async {
      final track = await extractor.extractMetadata('/path/- Title.mp3');
      expect(track.title, 'Title');
      expect(track.artist, '');
    });
  });

  group('Filename Parsing Edge Cases', () {
    late MacOSMetadataExtractor extractor;

    setUp(() {
      extractor = MacOSMetadataExtractor();
    });

    test('handles files with no extension', () async {
      final track = await extractor.extractMetadata('/path/Artist - Title');
      expect(track.title, 'Title');
      expect(track.artist, 'Artist');
    });

    test('handles files with multiple extensions', () async {
      final track = await extractor.extractMetadata('/path/Artist - Title.mp3.backup');
      expect(track.title, 'Title.mp3.backup');
      expect(track.artist, 'Artist');
    });

    test('handles separator at start of filename', () async {
      final track = await extractor.extractMetadata('/path/-Title.mp3');
      expect(track.title, 'Title');
      expect(track.artist, '');
    });

    test('handles separator at end of filename', () async {
      final track = await extractor.extractMetadata('/path/Artist-.mp3');
      expect(track.title, '');
      expect(track.artist, 'Artist');
    });
  });

  group('AndroidMetadataExtractor', () {
    test('with useFilenameOverride=true always uses filename parsing', () async {
      final extractor = AndroidMetadataExtractor(
        useFilenameOverride: true,
      );

      final track = await extractor.extractMetadata('/path/Artist - Title.mp3');
      expect(track.title, 'Title');
      expect(track.artist, 'Artist');
      expect(track.path, '/path/Artist - Title.mp3');
    });

    test('with useFilenameOverride=true skips MediaStore entirely', () async {
      // Even if MediaStore would fail, override mode should not call it
      final extractor = AndroidMetadataExtractor(
        useFilenameOverride: true,
      );

      final track = await extractor.extractMetadata('/path/Unknown - Song.mp3');
      expect(track.title, 'Song');
      expect(track.artist, 'Unknown');
      expect(track.path, '/path/Unknown - Song.mp3');
    });

    test('with useFilenameOverride=false falls back to filename when MediaStore fails', () async {
      final mockAudioQuery = MockOnAudioQueryEmpty();
      final extractor = AndroidMetadataExtractor(
        audioQuery: mockAudioQuery,
        useFilenameOverride: false,
      );

      final track = await extractor.extractMetadata('/path/Artist - Title.mp3');
      expect(track.title, 'Title');
      expect(track.artist, 'Artist');
      expect(track.path, '/path/Artist - Title.mp3');
    });

    test('default useFilenameOverride is false for backward compatibility', () async {
      final mockAudioQuery = MockOnAudioQueryEmpty();
      final extractor = AndroidMetadataExtractor(
        audioQuery: mockAudioQuery,
        // useFilenameOverride not specified, should default to false
      );

      // Should attempt MediaStore (which fails) and fall back to filename
      final track = await extractor.extractMetadata('/path/Artist - Title.mp3');
      expect(track.title, 'Title');
      expect(track.artist, 'Artist');
      expect(track.path, '/path/Artist - Title.mp3');
    });
  });
}

