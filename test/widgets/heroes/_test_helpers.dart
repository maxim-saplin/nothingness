import 'package:flutter/material.dart';
import 'package:nothingness/models/song_info.dart';
import 'package:nothingness/models/theme_id.dart';
import 'package:nothingness/providers/audio_player_provider.dart';
import 'package:nothingness/theme/themes.dart';
import 'package:provider/provider.dart';

/// A minimal AudioPlayerProvider fake for hero widget tests.
///
/// The real provider only mutates `_songInfo` from its controller / handler
/// callbacks. For pure visual unit tests we just need to inject a value and
/// emit `notifyListeners`.
class FakeAudioPlayerProvider extends AudioPlayerProvider {
  FakeAudioPlayerProvider({
    SongInfo? songInfo,
    List<double>? spectrumData,
    bool isPlaying = false,
  })  : _songInfoOverride = songInfo,
        _spectrumOverride = spectrumData,
        _isPlayingOverride = isPlaying;

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
  AudioPlayerProvider provider,
  Widget child, {
  Brightness brightness = Brightness.dark,
  ThemeId themeId = ThemeId.void_,
}) {
  return ChangeNotifierProvider<AudioPlayerProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: buildAppTheme(id: themeId, brightness: brightness),
      home: Scaffold(body: child),
    ),
  );
}
