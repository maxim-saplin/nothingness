import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/spectrum_settings.dart';
import 'spectrum_analyzer.dart';
import 'spectrum_provider.dart';

typedef VoiceHandleProvider = Future<SoundHandle?> Function();

/// Spectrum provider that polls SoLoud FFT data for the current voice handle.
class SoLoudSpectrumProvider implements SpectrumProvider {
  SoLoudSpectrumProvider({
    required SoLoud soloud,
    required VoiceHandleProvider handleProvider,
    SpectrumSettings initialSettings = const SpectrumSettings(),
  })  : _soloud = soloud,
        _handleProvider = handleProvider,
        _settings = initialSettings;

  final SoLoud _soloud;
  final VoiceHandleProvider _handleProvider;

  SpectrumSettings _settings;
  Timer? _timer;
  final _controller = StreamController<List<double>>.broadcast();
  List<double> _lastValues = const [];
  final AudioData _audioData = AudioData(GetSamplesKind.linear);
  final SpectrumAnalyzer _analyzer = SpectrumAnalyzer();

  @override
  Stream<List<double>> get spectrumStream => _controller.stream;

  @override
  Future<void> start() async {
    if (!_soloud.getVisualizationEnabled()) {
      _soloud.setVisualizationEnabled(true);
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) async {
      await _poll();
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void updateSettings(SpectrumSettings settings) {
    _settings = settings;
  }

  Future<void> _poll() async {
    final handle = await _handleProvider();
    if (handle == null) return;

    try {
      _audioData.updateSamples();
      final samples = _audioData.getAudioData();
      if (samples.length < 256) return;

      final fft = samples.sublist(0, 256);
      final bars = _analyzer.transform(
        fft: fft,
        barCount: _settings.barCount.count,
        noiseGateDb: _settings.noiseGateDb,
        previousValues: _lastValues,
        smoothing: _settings.decaySpeed.value,
      );
      _controller.add(bars);
      _lastValues = bars;
    } catch (e) {
      debugPrint('SoLoud spectrum poll error: $e');
    }
  }
}
