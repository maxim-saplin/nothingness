import 'package:flutter/material.dart';
import 'package:nothingness/models/song_info.dart';
import 'package:nothingness/models/theme_id.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/theme/themes.dart';
import 'package:provider/provider.dart';

import '../../services/mock_audio_transport.dart';

/// A minimal [PlaybackController] fake for hero/widget tests.
///
/// The real controller only mutates state from its transport / playlist
/// callbacks. For pure visual unit tests we just need to inject values and emit
/// `notifyListeners`, so we override the UI-facing getters directly and never
/// call [init] (no real audio plumbing is touched).
class FakeAudioPlayerProvider extends PlaybackController {
  FakeAudioPlayerProvider({
    SongInfo? songInfo,
    List<double>? spectrumData,
    bool isPlaying = false,
  })  : _songInfoOverride = songInfo,
        _spectrumOverride = spectrumData,
        _isPlayingOverride = isPlaying,
        super(transport: MockAudioTransport());

  SongInfo? _songInfoOverride;
  List<double>? _spectrumOverride;
  bool _isPlayingOverride;

  @override
  SongInfo? get songInfo => _songInfoOverride;

  @override
  List<double> get spectrumData =>
      _spectrumOverride ?? const <double>[0, 0, 0, 0];

  @override
  bool get isPlaying => _isPlayingOverride;

  void setSongInfo(SongInfo? info) {
    _songInfoOverride = info;
    notifyListeners();
  }

  void setSpectrum(List<double> data) {
    _spectrumOverride = data;
    notifyListeners();
  }

  void setIsPlaying(bool value) {
    _isPlayingOverride = value;
    notifyListeners();
  }
}

Widget wrapWithProvider(
  PlaybackController provider,
  Widget child, {
  Brightness brightness = Brightness.dark,
  ThemeId themeId = ThemeId.void_,
}) {
  return ChangeNotifierProvider<PlaybackController>.value(
    value: provider,
    child: MaterialApp(
      theme: buildAppTheme(id: themeId, brightness: brightness),
      home: Scaffold(body: child),
    ),
  );
}
