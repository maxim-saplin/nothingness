import 'dart:async';

import '../models/spectrum_settings.dart';
import '../services/audio_transport.dart';

enum FakeLoadOutcomeType { success, notFound, error }

class FakeLoadOutcome {
  final FakeLoadOutcomeType type;
  final Object? error;

  const FakeLoadOutcome._(this.type, this.error);

  const FakeLoadOutcome.success() : this._(FakeLoadOutcomeType.success, null);
  const FakeLoadOutcome.notFound() : this._(FakeLoadOutcomeType.notFound, null);
  const FakeLoadOutcome.error(Object error)
    : this._(FakeLoadOutcomeType.error, error);
}

/// Deterministic, test-friendly AudioTransport.
///
/// - `load()` emits Loaded/Error events and throws on failure.
/// - `emitEnded()` lets tests simulate "track ended naturally".
class FakeAudioTransport implements AudioTransport {
  final StreamController<TransportEvent> _events =
      StreamController<TransportEvent>.broadcast();

  final Map<String, FakeLoadOutcome> outcomesByPath;
  final Duration fixedDuration;

  String? _currentPath;
  bool _playing = false;
  Duration _position = Duration.zero;

  FakeAudioTransport({
    Map<String, FakeLoadOutcome>? outcomesByPath,
    this.fixedDuration = const Duration(seconds: 10),
  }) : outcomesByPath = outcomesByPath ?? <String, FakeLoadOutcome>{};

  @override
  Stream<TransportEvent> get eventStream => _events.stream;

  @override
  Future<Duration> get position async => _position;

  @override
  Future<Duration> get duration async =>
      _currentPath == null ? Duration.zero : fixedDuration;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  @override
  Future<void> load(String path, {String? title, String? artist}) async {
    _currentPath = path;
    _position = Duration.zero;

    final outcome = outcomesByPath[path] ?? const FakeLoadOutcome.success();
    switch (outcome.type) {
      case FakeLoadOutcomeType.success:
        _events.add(TransportLoadedEvent(path: path));
        return;
      case FakeLoadOutcomeType.notFound:
        final err = StateError('not_found: $path');
        _events.add(TransportErrorEvent(path: path, error: err));
        throw err;
      case FakeLoadOutcomeType.error:
        final err = outcome.error ?? StateError('load_error: $path');
        _events.add(TransportErrorEvent(path: path, error: err));
        throw err;
    }
  }

  @override
  Future<void> play() async {
    _playing = true;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _events.add(TransportPositionEvent(position: position));
  }

  @override
  Stream<List<double>> get spectrumStream => const Stream<List<double>>.empty();

  @override
  void updateSpectrumSettings(SpectrumSettings settings) {}

  @override
  void setCaptureEnabled(bool enabled) {}

  bool get isPlaying => _playing;
  String? get currentPath => _currentPath;

  void setOutcome(String path, FakeLoadOutcome outcome) {
    outcomesByPath[path] = outcome;
  }

  void emitEnded({String? path}) {
    final p = path ?? _currentPath;
    _events.add(TransportEndedEvent(path: p));
  }

  void reset() {
    outcomesByPath.clear();
    _currentPath = null;
    _playing = false;
    _position = Duration.zero;
  }
}
