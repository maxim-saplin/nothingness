import 'package:audio_session/audio_session.dart';

import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'fake_audio_transport.dart';

/// Shared singleton for integration tests (same isolate) to control the app.
class TestHarness {
  TestHarness._();

  static final TestHarness instance = TestHarness._();

  final FakeAudioTransport transport = FakeAudioTransport();

  PlaybackController? controller;

  /// Simulate a missing/unreadable track via a transport load failure (the
  /// source of truth — there is no separate File.exists() preflight).
  void setOutcomes(Map<String, FakeLoadOutcome> outcomes) {
    transport.outcomesByPath
      ..clear()
      ..addAll(outcomes);
  }

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    final c = controller;
    if (c == null) {
      throw StateError('TestHarness.controller is not initialized');
    }
    await c.setQueue(tracks, startIndex: startIndex, shuffle: shuffle);
  }

  void emitEnded() {
    transport.emitEnded();
  }

  /// Drive an audio interruption event through the controller.
  void simulateInterruption({required bool begin, required AudioInterruptionType type}) {
    final c = controller;
    if (c == null) {
      throw StateError('TestHarness.controller is not initialized');
    }
    c.debugSimulateInterruption(AudioInterruptionEvent(begin, type));
  }

  /// Drive a "becoming noisy" event through the controller.
  void simulateBecomingNoisy() {
    final c = controller;
    if (c == null) {
      throw StateError('TestHarness.controller is not initialized');
    }
    c.debugSimulateBecomingNoisy();
  }

  void reset() {
    transport.reset();
  }
}
