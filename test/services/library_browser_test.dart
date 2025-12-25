import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/library_browser.dart';

void main() {
  group('LibraryBrowser', () {
    test('buildVirtualListing groups songs into folders and files', () {
      final browser = LibraryBrowser(supportedExtensions: {'mp3', 'flac'});
      final songs = [
        const LibrarySong(path: '/storage/emulated/0/Music/song0.mp3', title: 'Root Song'),
        const LibrarySong(path: '/storage/emulated/0/Music/Rock/song1.mp3', title: 'Song 1'),
        const LibrarySong(path: '/storage/emulated/0/Music/Rock/live/song2.flac', title: 'Song 2'),
        const LibrarySong(path: '/storage/emulated/0/Music/Jazz/song3.mp3', title: 'Song 3'),
        const LibrarySong(path: '/storage/emulated/0/Music/Other/skip.txt', title: 'Skip'),
      ];

      final listing = browser.buildVirtualListing(
        basePath: '/storage/emulated/0/Music',
        songs: songs,
      );

      expect(listing.path, '/storage/emulated/0/Music');
      expect(listing.folders.map((f) => f.name), containsAll(['Jazz', 'Rock']));
      expect(listing.tracks.map((t) => t.title), contains('Root Song'));
      expect(listing.tracks.any((t) => t.title == 'Skip'), isFalse);
    });

    test('listFileSystem returns folders and supported files', () async {
      final root = await Directory.systemTemp.createTemp('library_browser_test');
      addTearDown(() => root.delete(recursive: true));

      final subDir = Directory('${root.path}/Rock');
      await subDir.create(recursive: true);
      final audioFile = File('${root.path}/track.mp3');
      await audioFile.writeAsString('data');
      final hiddenDir = Directory('${root.path}/.hidden');
      await hiddenDir.create();

      final browser = LibraryBrowser(supportedExtensions: {'mp3'});
      final listing = await browser.listFileSystem(root.path);

      expect(listing.path, root.path);
      expect(listing.folders.map((f) => f.name), contains('Rock'));
      expect(listing.folders.any((f) => f.name == '.hidden'), isFalse);
      expect(listing.tracks, hasLength(1));
      expect(listing.tracks.first.title, 'track');
    });
  });
}
