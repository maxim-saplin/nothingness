import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import 'mock_audio_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackController timer lifecycle', () {
    test('suspend/resume delegate to the transport', () {
      final transport = MockAudioTransport();
      final controller = PlaybackController(
        transport: transport,
        playlist: PlaylistStore(
          hiveInitializer: () async {},
        ),
      );

      controller.suspendTimers();
      controller.resumeTimers();

      expect(transport.suspendTimerCalls, 1);
      expect(transport.resumeTimerCalls, 1);

      controller.dispose();
    });
  });
}
