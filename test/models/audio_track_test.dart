import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/models/audio_track.dart';

void main() {
  group('AudioTrack', () {
    test('copyWith updates fields correctly', () {
      const track = AudioTrack(
        path: '/path/to/song.mp3',
        title: 'Original Title',
        artist: 'Original Artist',
        duration: Duration(seconds: 180),
      );

      final updated = track.copyWith(
        title: 'New Title',
        isNotFound: true,
      );

      expect(updated.path, track.path);
      expect(updated.title, 'New Title');
      expect(updated.artist, track.artist);
      expect(updated.duration, track.duration);
      expect(updated.isNotFound, true);
    });

    test('isNotFound defaults to false', () {
      const track = AudioTrack(
        path: '/path/to/song.mp3',
        title: 'Song',
      );
      expect(track.isNotFound, false);
    });

    test('artist defaults to empty string', () {
      const track = AudioTrack(
        path: '/path/to/song.mp3',
        title: 'Song',
      );
      expect(track.artist, '');
    });

    test('Hive adapter handles serialization', () async {
      // Initialize Hive in a temp directory
      final tempDir = await Directory.systemTemp.createTemp('hive_test');
      Hive.init(tempDir.path);
      
      // Register adapter
      if (!Hive.isAdapterRegistered(AudioTrackAdapter.kTypeId)) {
        Hive.registerAdapter(AudioTrackAdapter());
      }

      final box = await Hive.openBox<AudioTrack>('audio_tracks');
      
      const track = AudioTrack(
        path: '/path/to/song.mp3',
        title: 'Song',
        artist: 'Artist',
        duration: Duration(seconds: 200),
      );

      await box.put('key1', track);
      final retrieved = box.get('key1');

      expect(retrieved, isNotNull);
      expect(retrieved!.path, track.path);
      expect(retrieved.title, track.title);
      expect(retrieved.artist, track.artist);
      expect(retrieved.duration, track.duration);
      // isNotFound is transient, so it should be false (default) when read back
      // The adapter does not write isNotFound.
      expect(retrieved.isNotFound, false);

      await box.close();
      await tempDir.delete(recursive: true);
    });
  });
}
