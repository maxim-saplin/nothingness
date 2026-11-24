import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/services/soloud_spectrum_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SoLoud emits 128-bin FFT events on a native target', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final soloud = SoLoud.instance;
      final provider = SoLoudSpectrumProvider(soloud: soloud);
      AudioSource? source;
      SoundHandle? handle;

      await soloud.init();
      try {
        source = await soloud.loadMem('spectrum-smoke.wav', _toneWav());
        handle = soloud.play(source, volume: 0.5);
        final event = soloud.audioVisualizationEvents
            .firstWhere(
              (packet) => packet.fftData?.any((value) => value > 0.0) ?? false,
            )
            .timeout(const Duration(seconds: 5));
        final bars = provider.spectrumStream
            .firstWhere((values) => values.any((value) => value > 0.0))
            .timeout(const Duration(seconds: 5));
        await provider.start();

        final packet = await event;
        final fft = packet.fftData;
        final spectrum = await bars;
        expect(packet.channelCount, 1);
        expect(fft, isNotNull);
        expect(fft, hasLength(128));
        expect(
          fft!.every((value) => value.isFinite && value >= 0.0 && value <= 1.0),
          isTrue,
        );
        expect(spectrum, hasLength(const SpectrumSettings().barCount.count));
        expect(spectrum.any((value) => value > 0.0), isTrue);
      } finally {
        await provider.stop();
        if (soloud.isInitialized) {
          if (handle != null) await soloud.stop(handle);
          if (source != null) await soloud.disposeSource(source);
          soloud.deinit();
        }
      }
    });
  });
}

Uint8List _toneWav() {
  const sampleRate = 44100;
  const sampleCount = sampleRate ~/ 2;
  const bytesPerSample = 2;
  final dataSize = sampleCount * bytesPerSample;
  final bytes = Uint8List(44 + dataSize);
  final data = ByteData.sublistView(bytes);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * bytesPerSample, Endian.little);
  data.setUint16(32, bytesPerSample, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < sampleCount; i++) {
    final sample = (math.sin(2 * math.pi * 440 * i / sampleRate) * 12000)
        .round();
    data.setInt16(44 + i * bytesPerSample, sample, Endian.little);
  }

  return bytes;
}
