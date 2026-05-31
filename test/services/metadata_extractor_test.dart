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

/// Returns a single MediaStore song with the given title/artist for [data].
class MockOnAudioQuerySong extends OnAudioQuery {
  MockOnAudioQuerySong({required this.data, required this.title, this.artist});
  final String data;
  final String title;
  final String? artist;

  @override
  Future<List<SongModel>> querySongs({
    SongSortType? sortType,
    OrderType? orderType,
    UriType? uriType,
    bool? ignoreCase,
    String? path,
  }) async =>
      [SongModel({'_data': data, 'title': title, 'artist': artist})];
}

void main() {
  group('DesktopMetadataExtractor', () {
    late DesktopMetadataExtractor extractor;

    setUp(() {
      extractor = DesktopMetadataExtractor();
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

    // B-047: a filename that embeds the artist again in the title leaves the
    // artist in the title after the leftmost-separator split. The desktop path
    // must drop the redundant prefix — the same guard the Android path uses.
    test('drops a redundant artist prefix the filename embedded in the title',
        () async {
      final track = await extractor
          .extractMetadata('/path/Nirvana - Nirvana - Rape me.wav');
      expect(track.artist, 'Nirvana');
      expect(track.title, 'Rape me');
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
    late DesktopMetadataExtractor extractor;

    setUp(() {
      extractor = DesktopMetadataExtractor();
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

    // B-046: MediaStore returns the filename as the title for files with no ID3
    // title tag, so the artist gets repeated in the title ("Nirvana - Rape me"
    // with artist "Nirvana"). The title must drop the redundant prefix.
    test('drops an artist prefix MediaStore left embedded in the title', () async {
      final extractor = AndroidMetadataExtractor(
        audioQuery: MockOnAudioQuerySong(
          data: '/path/Nirvana - Rape me.mp3',
          title: 'Nirvana - Rape me',
          artist: 'Nirvana',
        ),
      );
      final track = await extractor.extractMetadata('/path/Nirvana - Rape me.mp3');
      expect(track.artist, 'Nirvana');
      expect(track.title, 'Rape me');
    });

    test('keeps a dash-bearing title whose prefix is not the artist', () async {
      final extractor = AndroidMetadataExtractor(
        audioQuery: MockOnAudioQuerySong(
          data: '/path/x.mp3',
          title: 'Sgt. Pepper - Reprise',
          artist: 'The Beatles',
        ),
      );
      final track = await extractor.extractMetadata('/path/x.mp3');
      expect(track.artist, 'The Beatles');
      expect(track.title, 'Sgt. Pepper - Reprise');
    });
  });
}

