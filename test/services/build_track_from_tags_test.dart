import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/metadata_extractor.dart';

/// Covers the query-free parse that replaced the O(N×M) per-song MediaStore
/// re-query (folder navigation/reshuffle now build from the cached scan tags).
void main() {
  group('buildTrackFromTags (tags win)', () {
    test('uses MediaStore title + artist verbatim', () {
      final t = buildTrackFromTags(
        path: '/m/song.mp3', rawTitle: 'Smells Like Teen Spirit', rawArtist: 'Nirvana');
      expect(t.title, 'Smells Like Teen Spirit');
      expect(t.artist, 'Nirvana');
    });

    test('B-047: drops an artist prefix embedded in the title', () {
      // MediaStore title carried the filename "Nirvana - Smells Like Teen Spirit".
      final t = buildTrackFromTags(
        path: '/m/x.mp3', rawTitle: 'Nirvana - Smells Like Teen Spirit', rawArtist: 'Nirvana');
      expect(t.artist, 'Nirvana');
      expect(t.title, 'Smells Like Teen Spirit');
    });

    test('keeps a dash that is not the artist', () {
      final t = buildTrackFromTags(
        path: '/m/x.mp3', rawTitle: 'Sgt. Pepper - Reprise', rawArtist: 'The Beatles');
      expect(t.title, 'Sgt. Pepper - Reprise');
    });

    test('empty title falls back to filename parsing (incl. track-number strip)', () {
      final t = buildTrackFromTags(
        path: '/m/02 - The Offspring - Pretty Fly.mp3', rawTitle: '', rawArtist: '');
      expect(t.artist, 'The Offspring');
      expect(t.title, 'Pretty Fly');
    });

    test('empty artist falls back to the filename-parsed artist', () {
      final t = buildTrackFromTags(
        path: '/m/Radiohead – Creep.wav', rawTitle: 'Creep', rawArtist: '');
      expect(t.artist, 'Radiohead'); // en-dash separator (U+2013)
      expect(t.title, 'Creep');
    });
  });

  group('buildTrackFromTags (filename override)', () {
    test('ignores tags and parses the filename when override is set', () {
      final t = buildTrackFromTags(
        path: '/m/Adele - Hello.wav',
        rawTitle: 'SomeTaggedTitle',
        rawArtist: 'SomeTaggedArtist',
        useFilenameOverride: true);
      expect(t.artist, 'Adele');
      expect(t.title, 'Hello');
    });
  });
}
