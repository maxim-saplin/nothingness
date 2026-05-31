import 'package:flutter_test/flutter_test.dart';

import 'package:nothingness/services/android_smart_roots.dart';

void main() {
  group('labelForPath', () {
    test('/storage/emulated/0/Music -> Music display, full path subtitle', () {
      final label = labelForPath('/storage/emulated/0/Music');
      expect(label.display, 'Music');
      expect(label.subtitle, '/storage/emulated/0/Music');
    });

    test('/storage/emulated/0 -> Internal, no subtitle', () {
      final label = labelForPath('/storage/emulated/0');
      expect(label.display, 'Internal');
      expect(label.subtitle, isNull);
    });

    test('/storage/ABCD-1234/Nextcloud/Music -> Music display, subtitle Nextcloud',
        () {
      final label = labelForPath('/storage/ABCD-1234/Nextcloud/Music');
      expect(label.display, 'Music');
      expect(label.subtitle, 'Nextcloud');
    });

    test('/storage/ABCD-1234 with isRemovable=true -> USB', () {
      final label = labelForPath('/storage/ABCD-1234', isRemovable: true);
      expect(label.display, 'USB');
      expect(label.subtitle, isNull);
    });

    test('/storage/ABCD-1234 with isRemovable=false -> Removable', () {
      final label = labelForPath('/storage/ABCD-1234', isRemovable: false);
      expect(label.display, 'Removable');
      expect(label.subtitle, isNull);
    });

    test('preserves case of basename for well-known folder', () {
      final label = labelForPath('/storage/emulated/0/Podcasts');
      expect(label.display, 'Podcasts');
    });

    test('case-insensitive match for well-known basenames', () {
      final label = labelForPath('/storage/emulated/0/music');
      // Display is the case-preserved basename from the path.
      expect(label.display, 'music');
      expect(label.subtitle, '/storage/emulated/0/music');
    });

    test('non-well-known nested path -> basename + full path subtitle', () {
      final label = labelForPath('/storage/emulated/0/Some/Deep/Stuff');
      expect(label.display, 'Stuff');
      expect(label.subtitle, '/storage/emulated/0/Some/Deep/Stuff');
    });

    test('trailing slash is tolerated', () {
      final label = labelForPath('/storage/emulated/0/Music/');
      expect(label.display, 'Music');
    });
  });

  group('fallbackDeviceLabel', () {
    test("fallbackDeviceLabel('/storage/emulated/0') -> 'Internal — all music'",
        () {
      expect(
        fallbackDeviceLabel('/storage/emulated/0'),
        'Internal — all music',
      );
    });

    test('fallbackDeviceLabel(/storage/UUID) -> Removable — all music', () {
      expect(
        fallbackDeviceLabel('/storage/ABCD-1234'),
        'Removable — all music',
      );
    });
  });
}
