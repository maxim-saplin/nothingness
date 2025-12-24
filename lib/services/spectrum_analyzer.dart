import 'dart:math' as math;

/// Analyzes raw FFT data to produce visualization-ready bars.
///
/// This class handles:
/// - Logarithmic frequency scaling (to match human hearing).
/// - Frequency weighting (boosting highs to compensate for pink noise).
/// - Smoothing (decay) over time.
/// - Normalization to a 0.0-1.0 range.
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
    double smoothing = 0.5,
  }) {
    if (fft.isEmpty) return List.filled(barCount, 0.0);

    final buckets = List<double>.filled(barCount, 0.0);

    // We skip the first bin (DC offset) usually.
    // Using a log scale from index 1 to fft.length.
    final double minIdx = 1.0;
    final double maxIdx = fft.length.toDouble();
    final double logMax = math.log(maxIdx);
    final double logMin = math.log(minIdx);

    for (int i = 0; i < barCount; i++) {
      // Calculate start and end indices for this bar on a logarithmic scale.
      // We want to map i=[0..barCount] to freq=[minIdx..maxIdx].
      final double logStart = logMin + (logMax - logMin) * (i / barCount);
      final double logEnd = logMin + (logMax - logMin) * ((i + 1) / barCount);

      final int startIdx = math.exp(logStart).floor();
      // Force the last bar to extend to the end of the FFT array to avoid
      // floating point precision issues missing the last bin.
      final int endIdx = (i == barCount - 1) 
          ? fft.length 
          : math.exp(logEnd).floor();

      // Ensure we have at least one bin and don't go out of bounds.
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

      // Apply frequency weighting (boost highs).
      // Audio naturally falls off at higher frequencies (pink noise).
      // We apply a linear boost from 1.0 (bass) to 4.0 (treble).
      final double weight = 1.0 + (i / barCount) * 3.0;
      peak *= weight;

      // Convert to dB.
      // math.max(peak, 1e-6) ensures we don't take log(0).
      final db = 20 * math.log(math.max(peak, 1e-6)) / math.ln10;

      // Normalize.
      // We use the noiseGateDb as the floor.
      // We assume a dynamic range of 50dB above the noise floor.
      final threshold = noiseGateDb;
      const dynamicRange = 50.0;
      final normalized = ((db - threshold) / dynamicRange).clamp(0.0, 1.0);

      // Smoothing (Decay).
      final previous =
          (previousValues != null && previousValues.length > i)
              ? previousValues[i]
              : 0.0;

      // If new value is higher, attack is instant.
      // If lower, decay by smoothing factor.
      final value =
          normalized > previous
              ? normalized
              : previous + (normalized - previous) * smoothing;

      buckets[i] = value;
    }

    return buckets;
  }
}
