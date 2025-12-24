import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/spectrum_analyzer.dart';

void main() {
  late SpectrumAnalyzer analyzer;

  setUp(() {
    analyzer = SpectrumAnalyzer();
  });

  test('transform returns correct number of bars', () {
    final fft = List.filled(256, 0.0);
    final result = analyzer.transform(
      fft: fft,
      barCount: 16,
      noiseGateDb: -60,
    );
    expect(result.length, 16);
  });

  test('transform handles silence correctly', () {
    final fft = List.filled(256, 0.0);
    final result = analyzer.transform(
      fft: fft,
      barCount: 16,
      noiseGateDb: -60,
    );
    expect(result.every((val) => val == 0.0), isTrue);
  });

  test('transform applies frequency weighting (highs are boosted)', () {
    // Create a signal with equal amplitude at low and high frequencies
    final fft = List.filled(256, 0.0);
    
    // Low frequency peak (index 2)
    // Use a small value so we don't hit the 1.0 ceiling
    // -60dB = 0.001
    fft[2] = 0.001;
    
    // High frequency peak (index 200)
    fft[200] = 0.001;

    final result = analyzer.transform(
      fft: fft,
      barCount: 16,
      noiseGateDb: -100, 
      smoothing: 0.0,
    );

    // Find the bars corresponding to these indices
    // We expect the high frequency bar to have a higher value due to weighting
    
    // Since we don't know exactly which bar index 2 and 200 fall into without calculation,
    // we can just check the max of the first half vs max of the second half.
    
    double maxLow = 0.0;
    for (int i = 0; i < 8; i++) {
      if (result[i] > maxLow) maxLow = result[i];
    }
    
    double maxHigh = 0.0;
    for (int i = 8; i < 16; i++) {
      if (result[i] > maxHigh) maxHigh = result[i];
    }

    expect(maxHigh, greaterThan(maxLow), reason: 'High frequencies should be boosted');
  });

  test('transform applies smoothing', () {
    final fft = List.filled(256, 1.0); // Max volume
    
    // First frame: full volume
    final frame1 = analyzer.transform(
      fft: fft,
      barCount: 8,
      noiseGateDb: -60,
      smoothing: 0.5,
    );
    
    expect(frame1.first, closeTo(1.0, 0.01));

    // Second frame: silence
    final fftSilence = List.filled(256, 0.0);
    final frame2 = analyzer.transform(
      fft: fftSilence,
      barCount: 8,
      noiseGateDb: -60,
      previousValues: frame1,
      smoothing: 0.5,
    );

    // Should not be 0.0 immediately, but decayed
    expect(frame2.first, closeTo(0.5, 0.01));
    
    // Third frame: silence again
    final frame3 = analyzer.transform(
      fft: fftSilence,
      barCount: 8,
      noiseGateDb: -60,
      previousValues: frame2,
      smoothing: 0.5,
    );
    
    expect(frame3.first, closeTo(0.25, 0.01));
  });

  test('logarithmic binning covers full range', () {
    // Put a peak at the very end
    final fft = List.filled(256, 0.0);
    fft[255] = 1.0;

    final result = analyzer.transform(
      fft: fft,
      barCount: 16,
      noiseGateDb: -60,
    );

    // The last bar should pick this up
    expect(result.last, greaterThan(0.0));
  });
}
