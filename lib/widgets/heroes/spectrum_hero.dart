import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../models/spectrum_settings.dart';
import '../../providers/audio_player_provider.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';
import '../spectrum_visualizer.dart';

/// Spectrum visualisation embedded in the Void hero slot.
///
/// Styled to align with the Void chrome — track title is rendered in the
/// same mono / [AppTypography.heroSize] / [AppPalette.fgPrimary] treatment
/// used by [VoidHero], and the bars are forced monochrome against the
/// active palette regardless of [SpectrumSettings.colorScheme] so they
/// inherit the theme's light / dark variant instead of fighting the
/// rest of the chrome with their own palette.
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
    final spectrumData = player.spectrumData;
    final track = player.songInfo?.track;
    final hasTrack = track != null;
    final parent = hasTrack && track.path.isNotEmpty
        ? p.basename(p.dirname(track.path))
        : '';

    // Three identical fgPrimary stops gives a monochrome bar regardless of
    // the cycle position (low / mid / hot all collapse to the same shade);
    // the visualiser still lerps between them but the result is uniform.
    final List<Color> voidBarColors = <Color>[
      palette.fgPrimary,
      palette.fgPrimary,
      palette.fgPrimary,
    ];

    // Vertically center the title + visualizer block so the hero stays
    // visually balanced when the Void chrome expands the hero into the
    // freed browser slot (swipe-up collapsed). At the default ~32 % hero
    // height the centered layout still looks natural — the visualizer's
    // fractional size (`spectrumHeightFactor` of half the slot) keeps
    // it readable without dominating.
    // B-026: estimate the text block's height from typography so the
    // visualiser slot below it can be capped to what actually fits.
    // The estimate matches the live Column above (`maxLines: 2` title
    // with `height: 1.18`, an 8-px gap to the optional parent crumb at
    // `hintSize` * 1.2). When no track is loaded the parent crumb is
    // hidden, so the gap+hint contribution drops out — keeping the
    // reservation tight rather than over-reserving.
    // Add a safety buffer on top of the line-height math: glyph ascent/
    // descent rounding plus leading half-pixels can push the actual
    // rendered text block several pixels above the analytic line height,
    // and the buffer keeps the visualiser capped just below the true
    // text extent so the outer Column never overshoots its slot. This is
    // critical at uiScale=2.5 where the hero slot collapses to ~118
    // logical px and a single-pixel overshoot is what produced the
    // RenderFlex exceptions in the first place.
    final double titleHeight = typography.heroSize * 1.18 * 2;
    final double crumbHeight = hasTrack ? 8 + typography.hintSize * 1.2 : 0;
    const double textBlockSafetyBuffer = 8.0;
    final double reservedTextHeight =
        titleHeight + crumbHeight + textBlockSafetyBuffer;
    const double textToVisualizerGap = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 0.7 of the hero slot times `spectrumHeightFactor` (default 0.45)
        // matches the prior layout's visualiser height (Expanded ≈ 0.7 H,
        // then FractionallySizedBox heightFactor 0.45).
        //
        // B-026: cap the visualiser height by what remains after the text
        // block + gap, and `floorToDouble()` to strip sub-pixel fractions
        // so the slot is integer-pixel stable across devices. At
        // `uiScale=2.5` the hero slot collapses to ~118 logical px and
        // text + gap + visualiser would otherwise exceed it by ~20-30
        // px; capping shrinks the visualiser first (its bars scale
        // gracefully) instead of dropping a RenderFlex overflow.
        final double wantedVisualizer =
            constraints.maxHeight * 0.7 * config.spectrumHeightFactor;
        final double remaining = math.max(
          0,
          constraints.maxHeight - reservedTextHeight - textToVisualizerGap,
        );
        final double visualizerHeight =
            math.min(wantedVisualizer, remaining).floorToDouble();
        // Hide the visualiser slot entirely when the squeeze leaves it
        // too tiny to host the bars + frequency labels — the visualiser
        // owns its own internal Column (Expanded bars + 8 px gap + hint-
        // sized labels) and would otherwise overflow internally. 24 px
        // is a conservative floor that fits the labels at `hintSize`.
        final bool showVisualizer = visualizerHeight >= 24.0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasTrack ? track.title : 'nothingness',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.fgPrimary,
                      fontFamily: typography.monoFamily,
                      fontSize: typography.heroSize,
                      letterSpacing: typography.heroLetterSpacing,
                      fontWeight: FontWeight.w300,
                      height: 1.18,
                    ),
                  ),
                  if (hasTrack) ...[
                    const SizedBox(height: 8),
                    Text(
                      parent,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.fgTertiary,
                        fontFamily: typography.monoFamily,
                        fontSize: typography.hintSize,
                        letterSpacing: 0.18,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showVisualizer) ...[
              const SizedBox(height: textToVisualizerGap),
              SizedBox(
                width: double.infinity,
                height: visualizerHeight,
                child: FractionallySizedBox(
                  widthFactor: config.spectrumWidthFactor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SpectrumVisualizer(
                      data: spectrumData,
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
