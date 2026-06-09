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
}