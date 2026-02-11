import 'dart:async';

import '../models/spectrum_settings.dart';
import 'spectrum_provider.dart';

/// Bridge that exposes a [SpectrumProvider]'s FFT stream to the UI layer.
///
/// On Android with SoLoud backend, the native Visualizer cannot start because
/// SoLoud doesn't expose an Android audio session id. This bridge re-uses the
/// existing SoLoud FFT polling (via `SoLoudSpectrumProvider` inside
/// `SoLoudTransport`) and pipes its data through a clean stream that
/// `AudioPlayerProvider` can subscribe to in place of the platform-channel
/// Visualizer stream.
class SoloudSpectrumBridge {
  SoloudSpectrumBridge({
    required Stream<List<double>> sourceStream,
  }) : _sourceStream = sourceStream;

  final Stream<List<double>> _sourceStream;
  final StreamController<List<double>> _controller =
      StreamController<List<double>>.broadcast();
  StreamSubscription<List<double>>? _sub;
  SpectrumSettings _settings = const SpectrumSettings();
  bool _running = false;

  /// Stream of FFT bar data for consumption by UI / provider.
  Stream<List<double>> get stream => _controller.stream;

  SpectrumSettings get settings => _settings;

  /// Start forwarding FFT data from the source stream.
  void start() {
    if (_running) return;
    _running = true;
    _sub = _sourceStream.listen(
      _controller.add,
      onError: _controller.addError,
    );
  }

  /// Stop forwarding FFT data.
  void stop() {
    _running = false;
    _sub?.cancel();
    _sub = null;
  }

  void updateSettings(SpectrumSettings settings) {
    _settings = settings;
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }
}
