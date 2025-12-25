import 'dart:async';

import '../models/spectrum_settings.dart';
import 'platform_channels.dart';
import 'spectrum_provider.dart';

/// Android-only spectrum provider that streams mic FFT from platform code.
class MicrophoneSpectrumProvider implements SpectrumProvider {
  MicrophoneSpectrumProvider({PlatformChannels? platformChannels})
      : _platformChannels = platformChannels ?? PlatformChannels();

  final PlatformChannels _platformChannels;
  StreamSubscription<List<double>>? _sub;
  final _controller = StreamController<List<double>>.broadcast();

  @override
  Stream<List<double>> get spectrumStream => _controller.stream;

  @override
  Future<void> start() async {
    _sub ??= _platformChannels.spectrumStream().listen(_controller.add);
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  void updateSettings(SpectrumSettings settings) {
    _platformChannels.updateSpectrumSettings(settings);
  }
}
