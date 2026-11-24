import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/spectrum_settings.dart';
import 'spectrum_analyzer.dart';

const _fftMinDecibels = -100.0;
const _fftMaxDecibels = 0.0;

/// Provides spectrum data as normalized buckets in the range 0..1.
abstract class SpectrumProvider {
  /// Stream of spectrum buckets updated in real-time.
  Stream<List<double>> get spectrumStream;

  /// Begin producing spectrum data.
  Future<void> start();

  /// Stop producing spectrum data and release resources.
  Future<void> stop();

  /// Update noise gate / bar count / decay tuning.
  void updateSettings(SpectrumSettings settings);
}

/// Spectrum provider that converts SoLoud visualization events into bars.
class SoLoudSpectrumProvider implements SpectrumProvider {
  SoLoudSpectrumProvider({
    required this._soloud,
    SpectrumSettings initialSettings = const SpectrumSettings(),
  }) : _settings = initialSettings;

  final SoLoud _soloud;

  SpectrumSettings _settings;
  final _controller = StreamController<List<double>>.broadcast();
  List<double> _lastValues = const [];
  final SpectrumAnalyzer _analyzer = SpectrumAnalyzer();
  StreamSubscription<AudioVisualizationData>? _subscription;

  @override
  Stream<List<double>> get spectrumStream => _controller.stream;

  @override
  Future<void> start() async {
    if (_soloud.minDecibels != _fftMinDecibels ||
        _soloud.maxDecibels != _fftMaxDecibels) {
      _soloud.setFftDecibelRange(_fftMinDecibels, _fftMaxDecibels);
    }
    if (!_soloud.getVisualizationEnabled()) {
      _soloud.setVisualizationEnabled(
        true,
        windowSize: 256,
        kind: VisualizationKind.fft,
        channel: VisualizationChannel.merged,
      );
    }
    _subscription ??=
        _soloud.audioVisualizationEvents.listen(_consumeVisualization);
  }

  @override
  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    final cancellation = subscription?.cancel();
    if (_soloud.isInitialized && _soloud.getVisualizationEnabled()) {
      _soloud.setVisualizationEnabled(false);
    }
    await cancellation;
  }

  @override
  void updateSettings(SpectrumSettings settings) {
    _settings = settings;
  }

  void _consumeVisualization(AudioVisualizationData data) {
    final fftData = data.fftData;
    if (fftData == null || fftData.isEmpty) return;

    // SoLoud emits FFT bins normalized from its configured dB range, while
    // SpectrumAnalyzer expects linear magnitudes.
    final minDecibels = _soloud.minDecibels;
    final decibelRange = _soloud.maxDecibels - minDecibels;
    final magnitudes = List<double>.generate(
      fftData.length,
      (index) {
        final normalized = fftData[index].clamp(0.0, 1.0);
        final decibels = minDecibels + normalized * decibelRange;
        return math.pow(10.0, decibels / 20.0).toDouble();
      },
      growable: false,
    );
    final bars = _analyzer.transform(
      fft: magnitudes,
      barCount: _settings.barCount.count,
      noiseGateDb: _settings.noiseGateDb,
      previousValues: _lastValues,
      smoothing: _settings.decaySpeed.value,
    );
    _controller.add(bars);
    _lastValues = bars;
  }
}
