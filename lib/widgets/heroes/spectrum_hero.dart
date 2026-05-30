import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../models/spectrum_settings.dart';
import '../../providers/audio_player_provider.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';
import '../spectrum_visualizer.dart';
import 'hero_title_block.dart';

/// Spectrum visualisation embedded in the Void hero slot. Styled like the Void chrome (title in the [VoidHero] treatment) and the bars are forced monochrome against the active palette regardless of [SpectrumSettings.colorScheme] so they inherit the theme variant.
class SpectrumHero extends StatelessWidget {
  const SpectrumHero({
    super.key,
    required this.config,
    required this.settings,
  });

  final SpectrumScreenConfig config;
  final SpectrumSettings settings;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final player = context.watch<AudioPlayerProvider>();
    final hasTrack = player.songInfo?.track != null;

    // Three identical fgPrimary stops collapse to a uniform monochrome bar; the visualiser still lerps between them.
    final voidBarColors = <Color>[
      palette.fgPrimary,
      palette.fgPrimary,
      palette.fgPrimary,
    ];

    // B-026: estimate the title block height from typography so the visualiser slot can be capped to fit. Mirrors HeroTitleBlock (maxLines:2 title at height 1.18; 8-px gap + hintSize*1.2 crumb only with a track). The safety buffer absorbs glyph rounding so the outer Column never overshoots (RenderFlex overflow at uiScale=2.5 where the slot is ~118 px).
    const double textBlockSafetyBuffer = 8.0;
    const double textToVisualizerGap = 16.0;
    final double reservedTextHeight = typography.heroSize * 1.18 * 2 +
        (hasTrack ? 8 + typography.hintSize * 1.2 : 0) +
        textBlockSafetyBuffer;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 0.7 H * spectrumHeightFactor matches the prior layout. B-026: cap by what remains after the text block + gap and floor to integer px so the visualiser shrinks first instead of overflowing.
        final wantedVisualizer =
            constraints.maxHeight * 0.7 * config.spectrumHeightFactor;
        final remaining = math.max(0,
            constraints.maxHeight - reservedTextHeight - textToVisualizerGap);
        final visualizerHeight =
            math.min(wantedVisualizer, remaining).floorToDouble();
        // Hide the visualiser slot when too small to host bars + frequency labels (it owns an internal Column that would overflow). 24 px is a conservative floor fitting labels at `hintSize`.
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const HeroTitleBlock(),
            if (visualizerHeight >= 24.0) ...[
              const SizedBox(height: textToVisualizerGap),
              SizedBox(
                width: double.infinity,
                height: visualizerHeight,
                child: FractionallySizedBox(
                  widthFactor: config.spectrumWidthFactor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SpectrumVisualizer(
                      data: player.spectrumData,
                      settings: settings,
                      colorsOverride: voidBarColors,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
