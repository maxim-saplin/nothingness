import 'dart:math' as math;

/// Analyzes raw FFT data into visualization-ready bars: log frequency scaling,
/// frequency weighting (boost highs vs pink noise), time smoothing (decay), and
/// normalization to 0.0-1.0.
class SpectrumAnalyzer {
  /// Transforms raw FFT data into visualization bars.
  ///
  /// [fft] Raw FFT data (usually 256 or 512 samples).
  /// [barCount] Number of bars to output.
  /// [noiseGateDb] Minimum decibel level to consider (e.g. -35.0).
  /// [previousValues] Last frame's values for smoothing (decay).
  /// [smoothing] Decay factor (0.0 = no smoothing, 1.0 = no change).
  List<double> transform({
    required List<double> fft,
    required int barCount,
    required double noiseGateDb,
    List<double>? previousValues,
    double smoothing = 0.3,
  }) {
    if (fft.isEmpty) return List.filled(barCount, 0.0);

    final buckets = List<double>.filled(barCount, 0.0);

    // Log scale from index 1 (skip bin 0 / DC offset) to fft.length.
    final double minIdx = 1.0;
    final double maxIdx = fft.length.toDouble();
    final double logMax = math.log(maxIdx);
    final double logMin = math.log(minIdx);

    for (int i = 0; i < barCount; i++) {
      // Map i=[0..barCount] to freq=[minIdx..maxIdx] on a log scale.
      final double logStart = logMin + (logMax - logMin) * (i / barCount);
      final double logEnd = logMin + (logMax - logMin) * ((i + 1) / barCount);

      final int startIdx = math.exp(logStart).floor();
      // Force last bar to the FFT end so float precision can't drop the last bin.
      final int endIdx = (i == barCount - 1)
          ? fft.length
          : math.exp(logEnd).floor();

      // At least one bin, clamped in bounds.
      final int actualStart = startIdx.clamp(0, fft.length - 1);
      final int actualEnd = math.max(
        actualStart + 1,
        endIdx.clamp(actualStart + 1, fft.length),
      );

      var peak = 0.0;
      for (int j = actualStart; j < actualEnd; j++) {
        final v = fft[j].abs();
        if (v > peak) peak = v;
      }

      // Frequency weighting: linear boost 1.0 (bass) → 4.0 (treble) to
      // compensate for natural high-frequency falloff (pink noise).
      final double weight = 1.0 + (i / barCount) * 3.0;
      peak *= weight;

      // To dB; max(peak, 1e-6) avoids log(0).
      final db = 20 * math.log(math.max(peak, 1e-6)) / math.ln10;

      // Normalize over a 50dB dynamic range above the noise-gate floor.
      final threshold = noiseGateDb;
      const dynamicRange = 50.0;
      final normalized = ((db - threshold) / dynamicRange).clamp(0.0, 1.0);

      // Smoothing: instant attack on rise, decay by smoothing factor on fall.
      final previous =
          (previousValues != null && previousValues.length > i)
              ? previousValues[i]
              : 0.0;
      final value =
          normalized > previous
              ? normalized
              : previous + (normalized - previous) * smoothing;

      buckets[i] = value;
    }

    return buckets;
  }
}
