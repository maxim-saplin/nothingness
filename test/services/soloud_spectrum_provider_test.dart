import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/services/soloud_spectrum_provider.dart';

void main() {
  group('SoLoudSpectrumProvider', () {
    late _FakeSoLoud soloud;
    late SoLoudSpectrumProvider provider;

    setUp(() {
      soloud = _FakeSoLoud();
      provider = SoLoudSpectrumProvider(
        soloud: soloud,
        initialSettings: const SpectrumSettings(),
      );
    });

    tearDown(() async {
      await provider.stop();
      await soloud.close();
    });

    test('start is idempotent and transforms 128-bin FFT events', () async {
      final frames = <List<double>>[];
      final subscription = provider.spectrumStream.listen(frames.add);

      await provider.start();
      await provider.start();
      soloud.emit(_fftPacket());
      await Future<void>.delayed(Duration.zero);

      expect(soloud.visualizationStates, [true]);
      expect(soloud.decibelRanges, [
        [-100.0, 0.0],
      ]);
      expect(frames, hasLength(1));
      expect(frames.single, hasLength(const SpectrumSettings().barCount.count));
      expect(frames.single.any((value) => value > 0.0), isTrue);
      expect(
        frames.single.every(
          (value) => value.isFinite && value >= 0.0 && value <= 1.0,
        ),
        isTrue,
      );

      await subscription.cancel();
    });

    test('converts normalized dB bins before applying the noise gate', () async {
      final frames = <List<double>>[];
      final subscription = provider.spectrumStream.listen(frames.add);

      await provider.start();
      soloud.emit(_fftPacket(0.2)); // -80 dB, below the default -35 dB gate.
      await Future<void>.delayed(Duration.zero);
      expect(frames.single.every((value) => value == 0.0), isTrue);

      soloud.emit(_fftPacket(0.8)); // -20 dB, above the default noise gate.
      await Future<void>.delayed(Duration.zero);
      expect(frames, hasLength(2));
      expect(frames.last.any((value) => value > 0.0), isTrue);

      await subscription.cancel();
    });

    test('stop cancels events and restart resumes delivery', () async {
      final frames = <List<double>>[];
      final subscription = provider.spectrumStream.listen(frames.add);

      await provider.start();
      await provider.stop();
      soloud.emit(_fftPacket());
      await Future<void>.delayed(Duration.zero);
      expect(frames, isEmpty);

      await provider.start();
      soloud.emit(_fftPacket());
      await Future<void>.delayed(Duration.zero);

      expect(soloud.visualizationStates, [true, false, true]);
      expect(frames, hasLength(1));

      await subscription.cancel();
    });

    test('rapid stop then start leaves the new subscription active', () async {
      final frames = <List<double>>[];
      final subscription = provider.spectrumStream.listen(frames.add);

      await provider.start();
      final stopping = provider.stop();
      final starting = provider.start();
      await Future.wait([stopping, starting]);

      soloud.emit(_fftPacket());
      await Future<void>.delayed(Duration.zero);

      expect(soloud.visualizationStates, [true, false, true]);
      expect(frames, hasLength(1));

      await subscription.cancel();
    });
  });
}

AudioVisualizationData _fftPacket([double level = 0.8]) => AudioVisualizationData(
  channelCount: 1,
  wave: const [],
  fft: [Float32List.fromList(List<double>.filled(128, level))],
);

class _FakeSoLoud implements SoLoud {
  final _events = StreamController<AudioVisualizationData>.broadcast();
  final visualizationStates = <bool>[];
  final decibelRanges = <List<double>>[];
  bool _visualizationEnabled = false;
  double _minDecibels = -100.0;
  double _maxDecibels = -30.0;

  @override
  Stream<AudioVisualizationData> get audioVisualizationEvents =>
      _events.stream;

  @override
  bool get isInitialized => true;

  @override
  bool getVisualizationEnabled() => _visualizationEnabled;

  @override
  double get minDecibels => _minDecibels;

  @override
  double get maxDecibels => _maxDecibels;

  @override
  void setFftDecibelRange(double minDecibels, double maxDecibels) {
    _minDecibels = minDecibels;
    _maxDecibels = maxDecibels;
    decibelRanges.add([minDecibels, maxDecibels]);
  }

  @override
  void setVisualizationEnabled(
    bool enabled, {
    int windowSize = 256,
    VisualizationKind kind = VisualizationKind.waveAndFft,
    int channel = VisualizationChannel.merged,
  }) {
    _visualizationEnabled = enabled;
    visualizationStates.add(enabled);
  }

  void emit(AudioVisualizationData data) => _events.add(data);

  Future<void> close() => _events.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
