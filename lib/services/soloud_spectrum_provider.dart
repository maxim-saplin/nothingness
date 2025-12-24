import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/spectrum_settings.dart';
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

  @override
  Stream<List<double>> get spectrumStream => _controller.stream;

  @override
  Future<void> start() async {
    if (!_soloud.getVisualizationEnabled()) {
      _soloud.setVisualizationEnabled(true);
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 50), (_) async {
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
      final bars = _toBars(fft, _settings.barCount.count, _settings.noiseGateDb);
      _controller.add(bars);
      _lastValues = bars;
    } catch (e) {
      debugPrint('SoLoud spectrum poll error: $e');
    }
  }

  List<double> _toBars(List<double> fft, int barCount, double noiseGateDb) {
    final bucketSize = (fft.length / barCount).floor().clamp(1, fft.length);
    final buckets = List<double>.filled(barCount, 0);

    for (int i = 0; i < barCount; i++) {
      final start = i * bucketSize;
      final end = math.min(start + bucketSize, fft.length);
      var peak = 0.0;
      for (int j = start; j < end; j++) {
        final v = fft[j].abs();
        if (v > peak) peak = v;
      }

      final db = 20 * math.log(math.max(peak, 1e-6)) / math.ln10;
      final threshold = noiseGateDb;
      final dynamicRange = 22.0;
      final normalized = ((db - threshold) / dynamicRange).clamp(0.0, 1.0);

      final previous = _lastValues.length > i ? _lastValues[i] : 0.0;
      final smoothing = _settings.decaySpeed.value;
      final value = normalized > previous
          ? normalized
          : previous + (normalized - previous) * smoothing;
      buckets[i] = value;
    }

    return buckets;
  }
}
