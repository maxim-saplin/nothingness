import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('audio source defaults to player', () {
    const settings = SpectrumSettings();
    expect(settings.audioSource, SettingsService.defaultAudioSource);
  });

  test('audio source persists through json', () {
    const settings = SpectrumSettings(audioSource: AudioSourceMode.microphone);
    final json = settings.toJson();
    final restored = SpectrumSettings.fromJson(json);
    expect(restored.audioSource, AudioSourceMode.microphone);
  });
}
