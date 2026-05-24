import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/providers/audio_player_provider.dart';
import 'package:nothingness/services/automation_intent_service.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import 'mock_audio_transport.dart';

/// Subclass of [AudioPlayerProvider] that counts [playPause] calls and
/// flips a controllable `isPlaying`, so the dispatch logic can be exercised
/// without touching real audio plumbing.
class _CountingProvider extends AudioPlayerProvider {
  _CountingProvider({required bool initiallyPlaying})
    : _playing = initiallyPlaying,
      super.forTests(
        controller: PlaybackController(
          transport: MockAudioTransport(),
          playlist: PlaylistStore(hiveInitializer: () async {}),
        ),
        transport: MockAudioTransport(),
      );

  bool _playing;
  int playPauseCalls = 0;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> playPause() async {
    playPauseCalls++;
    _playing = !_playing;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.saplin.nothingness/automation');

  group('AutomationIntentService', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('start() drains a cold-start play action', () async {
      _registerNativeStub(pending: 'play');
      final provider = _CountingProvider(initiallyPlaying: false);
      final service = AutomationIntentService(provider, channel: channel);

      await service.start();

      expect(provider.playPauseCalls, 1);
      expect(provider.isPlaying, true);
    });

    test(
      'start() drains a cold-start pause action when nothing is playing (no-op)',
      () async {
        _registerNativeStub(pending: 'pause');
        final provider = _CountingProvider(initiallyPlaying: false);
        final service = AutomationIntentService(provider, channel: channel);

        await service.start();

        expect(provider.playPauseCalls, 0);
        expect(provider.isPlaying, false);
      },
    );

    test('start() with no pending action does nothing', () async {
      _registerNativeStub(pending: null);
      final provider = _CountingProvider(initiallyPlaying: false);
      final service = AutomationIntentService(provider, channel: channel);

      await service.start();

      expect(provider.playPauseCalls, 0);
    });

    test('warm-start play resumes only when paused', () async {
      _registerNativeStub(pending: null);
      final provider = _CountingProvider(initiallyPlaying: false);
      final service = AutomationIntentService(provider, channel: channel);
      await service.start();

      await _pushAction('play');
      expect(provider.playPauseCalls, 1);
      expect(provider.isPlaying, true);

      // Already playing — second PLAY is a no-op.
      await _pushAction('play');
      expect(provider.playPauseCalls, 1);
    });

    test('warm-start pause pauses only when playing', () async {
      _registerNativeStub(pending: null);
      final provider = _CountingProvider(initiallyPlaying: true);
      final service = AutomationIntentService(provider, channel: channel);
      await service.start();

      await _pushAction('pause');
      expect(provider.playPauseCalls, 1);
      expect(provider.isPlaying, false);

      // Already paused — second PAUSE is a no-op.
      await _pushAction('pause');
      expect(provider.playPauseCalls, 1);
    });

    test('warm-start playPause is an unconditional toggle', () async {
      _registerNativeStub(pending: null);
      final provider = _CountingProvider(initiallyPlaying: false);
      final service = AutomationIntentService(provider, channel: channel);
      await service.start();

      await _pushAction('playPause');
      expect(provider.playPauseCalls, 1);
      expect(provider.isPlaying, true);

      await _pushAction('playPause');
      expect(provider.playPauseCalls, 2);
      expect(provider.isPlaying, false);
    });

    test('unknown action tokens are ignored', () async {
      _registerNativeStub(pending: null);
      final provider = _CountingProvider(initiallyPlaying: false);
      final service = AutomationIntentService(provider, channel: channel);
      await service.start();

      await _pushAction('explode');
      expect(provider.playPauseCalls, 0);
    });

    test('start() is idempotent', () async {
      _registerNativeStub(pending: 'play');
      final provider = _CountingProvider(initiallyPlaying: false);
      final service = AutomationIntentService(provider, channel: channel);

      await service.start();
      await service.start(); // second call is a no-op

      expect(provider.playPauseCalls, 1);
    });
  });
}

/// Pretend to be the Kotlin side of the channel: respond to
/// `consumePendingAutomationAction` with the given value. One-shot — clears
/// itself after the first call to mirror the native semantics.
void _registerNativeStub({required String? pending}) {
  var drained = false;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.saplin.nothingness/automation'),
        (call) async {
          if (call.method == 'consumePendingAutomationAction') {
            if (drained) return null;
            drained = true;
            return pending;
          }
          return null;
        },
      );
}

/// Simulate a warm-start `onNewIntent` push from Kotlin by invoking the
/// Dart-side handler directly through the messenger.
Future<void> _pushAction(String action) async {
  const codec = StandardMethodCodec();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'com.saplin.nothingness/automation',
        codec.encodeMethodCall(MethodCall('onAutomationAction', action)),
        (_) {},
      );
}
