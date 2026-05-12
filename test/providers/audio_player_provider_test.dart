import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/providers/audio_player_provider.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import '../services/mock_audio_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioPlayerProvider timer lifecycle', () {
    test('non-Android path delegates suspend/resume to controller transport', () {
      final transport = MockAudioTransport();
      final controller = PlaybackController(
        transport: transport,
        playlist: PlaylistStore(
          hiveInitializer: () async {},
        ),
      );
      final provider = AudioPlayerProvider(
        controller: controller,
        transport: transport,
        isAndroidOverride: false,
      );

      provider.suspendTimers();
      provider.resumeTimers();

      expect(transport.suspendTimerCalls, 1);
      expect(transport.resumeTimerCalls, 1);

      provider.dispose();
    });

    test('Android path does not suspend or resume the live transport', () {
      final transport = MockAudioTransport();
      final controller = PlaybackController(
        transport: transport,
        playlist: PlaylistStore(
          hiveInitializer: () async {},
        ),
      );
      final provider = AudioPlayerProvider(
        controller: controller,
        transport: transport,
        isAndroidOverride: true,
      );

      provider.suspendTimers();
      provider.resumeTimers();

      expect(transport.suspendTimerCalls, 0);
      expect(transport.resumeTimerCalls, 0);

      provider.dispose();
    });
  });
}