import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/track_search_index.dart';

void main() {
  test('searches title, artist, and basename case-insensitively', () {
    const track = AudioTrack(
      path: 'webdav://source/Music/Adele%20-%20Hello.flac',
      title: 'Hello',
      artist: 'Adele',
    );
    final index = TrackSearchIndex([track]);

    expect(index.search('hello'), [track]);
    expect(index.search('ADELE'), [track]);
    expect(index.search('hello.flac'), [track]);
  });

  test('deduplicates paths and searches a 25K-track playlist', () {
    final tracks = List<AudioTrack>.generate(
      25000,
      (i) => AudioTrack(
        path: 'webdav://source/Music/Track%20$i.flac',
        title: i == 24999 ? 'Unique Needle Song' : 'Track $i',
        artist: i == 24999 ? 'Rare Artist' : 'Artist ${i % 100}',
      ),
    );
    final index = TrackSearchIndex([
      ...tracks,
      const AudioTrack(
        path: 'webdav://source/Music/Track%2024999.flac',
        title: 'Duplicate',
      ),
    ]);

    expect(index.length, 25000);
    expect(index.search('needle'), [tracks.last]);
    expect(index.search('rare artist'), [tracks.last]);
  });
}
