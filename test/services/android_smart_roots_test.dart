import 'package:flutter_test/flutter_test.dart';

import 'package:nothingness/services/android_smart_roots.dart';
import 'package:nothingness/services/library_browser.dart';

void main() {
  group('AndroidSmartRoots', () {
    test('single device clustered under Music -> one smart entry', () {
      final roots = const ['/storage/emulated/0'];
      final songs = const [
        LibrarySong(path: '/storage/emulated/0/Music/Rock/1.mp3', title: '1'),
        LibrarySong(path: '/storage/emulated/0/Music/Jazz/2.mp3', title: '2'),
      ];

      final sections = AndroidSmartRoots.compute(
        deviceRoots: roots,
        songs: songs,
        maxEntriesPerDevice: 5,
      );

      expect(sections, hasLength(1));
      expect(sections.single.deviceRoot, '/storage/emulated/0');
      expect(sections.single.entries, ['/storage/emulated/0/Music']);
    });

    test('split Music and Downloads/Music -> two smart entries', () {
      final roots = const ['/storage/emulated/0'];
      final songs = const [
        LibrarySong(path: '/storage/emulated/0/Music/Rock/1.mp3', title: '1'),
        LibrarySong(
          path: '/storage/emulated/0/Downloads/Music/2.mp3',
          title: '2',
        ),
      ];

      final sections = AndroidSmartRoots.compute(
        deviceRoots: roots,
        songs: songs,
        maxEntriesPerDevice: 5,
      );

      expect(sections.single.entries, [
        '/storage/emulated/0/Downloads/Music',
        '/storage/emulated/0/Music',
      ]);
    });

    test('internal and USB roots become separate sections', () {
      final roots = const ['/storage/emulated/0', '/storage/ABCD-1234'];
      final songs = const [
        LibrarySong(path: '/storage/emulated/0/Music/1.mp3', title: '1'),
        LibrarySong(path: '/storage/ABCD-1234/Music/2.mp3', title: '2'),
      ];

      final sections = AndroidSmartRoots.compute(
        deviceRoots: roots,
        songs: songs,
        maxEntriesPerDevice: 5,
      );

      expect(sections.map((s) => s.deviceRoot), [
        '/storage/ABCD-1234',
        '/storage/emulated/0',
      ]);
      expect(
        sections
            .firstWhere((s) => s.deviceRoot == '/storage/emulated/0')
            .entries,
        ['/storage/emulated/0/Music'],
      );
      expect(
        sections
            .firstWhere((s) => s.deviceRoot == '/storage/ABCD-1234')
            .entries,
        ['/storage/ABCD-1234/Music'],
      );
    });

    test('flood case (>max entries) falls back to device root', () {
      final roots = const ['/storage/emulated/0'];
      final songs = const [
        LibrarySong(path: '/storage/emulated/0/A/1.mp3', title: '1'),
        LibrarySong(path: '/storage/emulated/0/B/2.mp3', title: '2'),
        LibrarySong(path: '/storage/emulated/0/C/3.mp3', title: '3'),
        LibrarySong(path: '/storage/emulated/0/D/4.mp3', title: '4'),
        LibrarySong(path: '/storage/emulated/0/E/5.mp3', title: '5'),
        LibrarySong(path: '/storage/emulated/0/F/6.mp3', title: '6'),
      ];

      final sections = AndroidSmartRoots.compute(
        deviceRoots: roots,
        songs: songs,
        maxEntriesPerDevice: 5,
      );

      expect(sections.single.entries, ['/storage/emulated/0']);
    });

    test('redundancy removal: do not list parent+child', () {
      final roots = const ['/storage/emulated/0'];
      final songs = const [
        LibrarySong(path: '/storage/emulated/0/Music/1.mp3', title: '1'),
        LibrarySong(path: '/storage/emulated/0/Music/Rock/2.mp3', title: '2'),
      ];

      final sections = AndroidSmartRoots.compute(
        deviceRoots: roots,
        songs: songs,
        maxEntriesPerDevice: 5,
      );

      expect(sections.single.entries, ['/storage/emulated/0/Music']);
    });
  });
}
