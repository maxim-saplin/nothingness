import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/widgets/heroes/spectrum_hero.dart';
import 'package:nothingness/widgets/spectrum_visualizer.dart';

import '_test_helpers.dart';

void main() {
  testWidgets('renders the spectrum visualiser', (tester) async {
    final provider = FakeAudioPlayerProvider(
      spectrumData: List<double>.filled(32, 0.5),
    );
    await tester.pumpWidget(
      wrapWithProvider(
        provider,
        const SpectrumHero(
          config: SpectrumScreenConfig(),
          settings: SpectrumSettings(),
        ),
      ),
    );
    expect(find.byType(SpectrumVisualizer), findsOneWidget);
  });

  testWidgets('respects spectrumWidthFactor / heightFactor from config', (
    tester,
  ) async {
    final provider = FakeAudioPlayerProvider();
    const config = SpectrumScreenConfig(
      spectrumWidthFactor: 0.5,
      spectrumHeightFactor: 0.4,
    );
    // Constrain to a known size so we can predict the visualiser slot.
    await tester.pumpWidget(
      wrapWithProvider(
        provider,
        const SizedBox(
          width: 400,
          height: 600,
          child: SpectrumHero(
            config: config,
            settings: SpectrumSettings(),
          ),
        ),
      ),
    );

    // Width factor still flows through FractionallySizedBox.
    final fractional = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fractional.widthFactor, 0.5);

    // Height factor is now baked into the visualiser SizedBox height
    // (constraints.maxHeight * 0.7 * spectrumHeightFactor).
    final visualizerBox = tester.getSize(find.byType(SpectrumVisualizer));
    expect(visualizerBox.height, closeTo(600 * 0.7 * 0.4, 0.5));
  });
}
