import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/spectrum_settings.dart';
import 'audio_transport.dart';

/// Owns the live spectrum (FFT) frame off [AudioTransport]: the latest data,
/// capture toggling, and settings. Notifies on each new frame. Extracted from
/// [PlaybackController] so playback logic doesn't also manage spectrum state.
class SpectrumSource extends ChangeNotifier {
  SpectrumSource(this._transport);

  final AudioTransport _transport;
  StreamSubscription<List<double>>? _sub;
  List<double> _data = List<double>.filled(32, 0.0);

  List<double> get data => _data;
  Stream<List<double>> get stream => _transport.spectrumStream;
  void setCaptureEnabled(bool enabled) => _transport.setCaptureEnabled(enabled);
  void updateSettings(SpectrumSettings settings) =>
      _transport.updateSpectrumSettings(settings);

  /// Begin mirroring the transport's spectrum stream into [data].
  void start() {
    _sub ??= _transport.spectrumStream.listen((d) {
      _data = d;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
