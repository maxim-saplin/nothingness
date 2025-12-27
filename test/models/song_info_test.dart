import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/song_info.dart';

void main() {
  group('SongInfo', () {
    test('fromMap creates valid instance with complete data', () {
      final map = {
        'path': '/path/to/song.mp3',
        'title': 'Test Song',
        'artist': 'Test Artist',
        'album': 'Test Album',
        'isPlaying': true,
        'position': 1000,
        'duration': 5000,
      };

      final songInfo = SongInfo.fromMap(map);

      expect(songInfo.track.path, '/path/to/song.mp3');
      expect(songInfo.title, 'Test Song');
      expect(songInfo.artist, 'Test Artist');
      expect(songInfo.album, ''); // album getter always returns empty string
      expect(songInfo.isPlaying, true);
      expect(songInfo.position, 1000);
      expect(songInfo.duration, 5000);
    });

    test('fromMap handles null values with defaults', () {
      final map = {};

      final songInfo = SongInfo.fromMap(map);

      expect(songInfo.track.path, '');
      expect(songInfo.title, 'Unknown');
      expect(songInfo.artist, '');
      expect(songInfo.album, '');
      expect(songInfo.isPlaying, false);
      expect(songInfo.position, 0);
      expect(songInfo.duration, 0);
    });

    test('fromMap handles type mismatches gracefully', () {
      final mixedMap = {
        'path': '/path/to/song.mp3',
        'position': 100.5, // double
        'duration': 500, // int
      };

      final songMixed = SongInfo.fromMap(mixedMap);
      expect(songMixed.position, 100);
      expect(songMixed.duration, 500);
    });

    test('convenience getters delegate to track', () {
      const track = AudioTrack(
        path: '/path/to/song.mp3',
        title: 'Test Title',
        artist: 'Test Artist',
      );

      const songInfo = SongInfo(
        track: track,
        isPlaying: true,
        position: 1000,
        duration: 5000,
      );

      expect(songInfo.title, 'Test Title');
      expect(songInfo.artist, 'Test Artist');
      expect(songInfo.album, ''); // Always empty string
      expect(songInfo.track, track);
    });
  });
}
