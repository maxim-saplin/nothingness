import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../models/spectrum_settings.dart';
import '../../services/playback_controller.dart';
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
    final player = context.watch<PlaybackController>();
    final hasTrack = player.songInfo?.track != null;

    // Three identical fgPrimary stops collapse to a uniform monochrome bar; the visualiser still lerps between them.
    final voidBarColors = <Color>[
      palette.fgPrimary,
      palette.fgPrimary,
      palette.fgPrimary,
    ];

    // B-026: cap the visualiser to what's left after the title block so the
    // outer Column can't overflow a squeezed hero slot. Reserve both heading
    // lines at their worst case (2 lines each, 1.18 line height) plus a buffer
    // for glyph rounding.
    const double textBlockSafetyBuffer = 8.0;
    const double textToVisualizerGap = 16.0;
    final double h1Size = typography.heroSize * config.textScale;
    final double h2Size =
        typography.heroSize * heroSongSizeFactor * config.textScale;
    final double reservedTextHeight = h1Size * 1.18 * 2 +
        (hasTrack ? 8 + h2Size * 1.18 * 2 : 0) +
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
            HeroTitleBlock(textScale: config.textScale),
            if (visualizerHeight >= 24.0) ...[
              const SizedBox(height: textToVisualizerGap),
              SizedBox(
                width: double.infinity,
                height: visualizerHeight,
                child: FractionallySizedBox(
                  widthFactor: config.spectrumWidthFactor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    // The visualizer builds ONCE; its painter repaints per
                    // spectrum frame off spectrumListenable (paint phase only) —
                    // no 60fps widget rebuild.
                    child: SpectrumVisualizer(
                      repaint: player.spectrumListenable,
                      dataSource: () => player.spectrumData,
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
