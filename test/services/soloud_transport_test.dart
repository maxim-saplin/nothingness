import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/soloud_transport.dart';

void main() {
  group('SoLoudTransport.shouldPreloadPath', () {
    test('disables speculative preload for opus files', () {
      expect(SoLoudTransport.shouldPreloadPath('/music/example.opus'), isFalse);
    });

    test('keeps speculative preload for non-opus files', () {
      expect(SoLoudTransport.shouldPreloadPath('/music/example.mp3'), isTrue);
      expect(SoLoudTransport.shouldPreloadPath('/music/example.flac'), isTrue);
    });
  });

  group('SoLoudTransport paused position', () {
    test('reports the seeked position while no handle is live', () async {
      final transport = SoLoudTransport();
      await transport.seekWithinCurrentTrack(const Duration(seconds: 42));
      expect(await transport.position, const Duration(seconds: 42));
    });
  });

  test('keeps native Opus streaming fork pinned', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('flutter_soloud:\n    path: ./soloud'),
    );
    expect(File('soloud/src/audiobuffer/opus_stream.cpp').existsSync(), isTrue);
    expect(
      File('soloud/src/player.cpp').readAsStringSync(),
      contains('TYPE_OPUS_STREAM'),
    );
  });
}
