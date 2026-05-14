import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults match SettingsService statics', () {
    const settings = SpectrumSettings();
    expect(settings.noiseGateDb, SettingsService.defaultNoiseGateDb);
    expect(settings.barCount, SettingsService.defaultBarCount);
    expect(settings.colorScheme, SettingsService.defaultColorScheme);
    expect(settings.barStyle, SettingsService.defaultBarStyle);
    expect(settings.decaySpeed, SettingsService.defaultDecaySpeed);
  });

  test('round-trip through json preserves all fields', () {
    const settings = SpectrumSettings(
      noiseGateDb: -42.0,
      barCount: BarCount.bars12,
      colorScheme: SpectrumColorScheme.cyan,
      barStyle: BarStyle.glow,
      decaySpeed: DecaySpeed.slow,
    );
    final restored = SpectrumSettings.fromJson(settings.toJson());
    expect(restored.noiseGateDb, settings.noiseGateDb);
    expect(restored.barCount, settings.barCount);
    expect(restored.colorScheme, settings.colorScheme);
    expect(restored.barStyle, settings.barStyle);
    expect(restored.decaySpeed, settings.decaySpeed);
  });
}
