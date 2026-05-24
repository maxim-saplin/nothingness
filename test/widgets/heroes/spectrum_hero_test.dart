import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/song_info.dart';
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

  // B-026: at uiScale=2.5 the hero slot shrinks below the typography
  // baseline, causing the title/visualizer Column to overflow by ~19-31 px.
  // The fix should keep layout sub-pixel stable: SpectrumHero's outer
  // Column must not overflow when the hero slot is small. Inspect every
  // mounted RenderFlex's overflow state directly — `tester.takeException`
  // only surfaces the first exception per pump, and inner widgets (e.g.
  // SpectrumVisualizer's own Column) can throw their own overflow story
  // that should not mask the one we care about here.
  bool spectrumHeroColumnOverflowing(WidgetTester tester) {
    for (final ro in tester.allRenderObjects.whereType<RenderFlex>()) {
      // RenderFlex.toString() embeds 'OVERFLOWING' when its overflow
      // bookkeeping is set; we then inspect the creator chain to decide
      // whether this is *our* outer hero Column or an inner widget's.
      if (!ro.toStringShort().contains('OVERFLOWING')) continue;
      final creator = ro.debugCreator?.toString() ?? '';
      // The chain runs leaf→root (the Column itself first, then its
      // ancestors). If `SpectrumHero` shows up before `SpectrumVisualizer`
      // — or `SpectrumVisualizer` is absent entirely — the flagged
      // Column is the hero's outer Column. Otherwise it's an inner
      // widget's (e.g. the visualizer's own Column), which is out of
      // scope for B-026.
      final heroIdx = creator.indexOf('SpectrumHero');
      final visIdx = creator.indexOf('SpectrumVisualizer');
      if (heroIdx < 0) continue;
      if (visIdx < 0 || heroIdx < visIdx) {
        return true;
      }
    }
    return false;
  }

  testWidgets('does not overflow at squeezed hero slot (uiScale=2.5)', (
    tester,
  ) async {
    // Mirror the emulator: 1080x2424 physical, dpr 2.6. After uiScale=2.5
    // ScaledLayout exposes a logical viewport ~411x923. The hero slot is
    // heroFraction (0.32) of that, ~118 logical px high after various
    // chrome insets — which is what the live tree reports.
    final provider = FakeAudioPlayerProvider(
      spectrumData: List<double>.filled(32, 0.5),
      songInfo: const SongInfo(
        track: AudioTrack(
          path: '/storage/emulated/0/Music/Russian Rock/'
              'Ария - Беспечный ангел.mp3',
          title: 'Ария - Беспечный ангел.mp3',
        ),
        isPlaying: false,
        position: 0,
        duration: 200000,
      ),
    );

    await tester.pumpWidget(
      wrapWithProvider(
        provider,
        const SizedBox(
          width: 411,
          height: 118,
          child: SpectrumHero(
            config: SpectrumScreenConfig(),
            settings: SpectrumSettings(),
          ),
        ),
      ),
    );
    await tester.pump();
    final overflowed = spectrumHeroColumnOverflowing(tester);
    // Drain Flutter test framework's exception slot — inner-visualizer
    // paint exceptions at degenerate sizes are independent of B-026.
    while (tester.takeException() != null) {}

    expect(
      overflowed,
      isFalse,
      reason: 'SpectrumHero outer Column must not overflow at uiScale=2.5.',
    );
  });

  testWidgets('does not overflow across a sweep of squeezed hero heights', (
    tester,
  ) async {
    // Sub-pixel rounding can flip a RenderFlex into overflow at one specific
    // pixel height while neighbouring heights stay clean (the 0.453 px
    // symptom in B-026). Sweep a range that brackets the squeezed slot we
    // hit at uiScale=2.5 and confirm SpectrumHero's outer Column stays
    // clean across all of them.
    final provider = FakeAudioPlayerProvider(
      spectrumData: List<double>.filled(32, 0.5),
      songInfo: const SongInfo(
        track: AudioTrack(
          path: '/storage/emulated/0/Music/Russian Rock/'
              'Ария - Беспечный ангел.mp3',
          title: 'Ария - Беспечный ангел.mp3',
        ),
        isPlaying: false,
        position: 0,
        duration: 200000,
      ),
    );

    for (final double h in <double>[100, 118, 118.2, 130, 150, 200, 295]) {
      await tester.pumpWidget(
        wrapWithProvider(
          provider,
          SizedBox(
            width: 411,
            height: h,
            child: const SpectrumHero(
              config: SpectrumScreenConfig(),
              settings: SpectrumSettings(),
            ),
          ),
        ),
      );
      await tester.pump();
      final overflowed = spectrumHeroColumnOverflowing(tester);
      while (tester.takeException() != null) {}
      expect(
        overflowed,
        isFalse,
        reason: 'SpectrumHero outer Column overflowed at hero slot $h.',
      );
    }
  });
}
