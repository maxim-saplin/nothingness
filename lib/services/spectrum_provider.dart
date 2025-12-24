import '../models/spectrum_settings.dart';

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
