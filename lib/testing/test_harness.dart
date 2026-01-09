import '../models/audio_track.dart';
import '../services/playback_controller.dart';
import 'fake_audio_transport.dart';

/// Shared singleton for integration tests (same isolate) to control the app.
class TestHarness {
  TestHarness._();

  static final TestHarness instance = TestHarness._();

  final FakeAudioTransport transport = FakeAudioTransport();

  final Map<String, bool> _existsByPath = <String, bool>{};

  PlaybackController? controller;

  Future<bool> fileExists(String path) async => _existsByPath[path] ?? true;

  void setExists(String path, bool exists) {
    _existsByPath[path] = exists;
  }

  void setOutcomes(Map<String, FakeLoadOutcome> outcomes) {
    transport.outcomesByPath
      ..clear()
      ..addAll(outcomes);
  }

  void setExistsMap(Map<String, bool> existsByPath) {
    _existsByPath
      ..clear()
      ..addAll(existsByPath);
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

  void reset() {
    transport.reset();
    _existsByPath.clear();
  }
}
