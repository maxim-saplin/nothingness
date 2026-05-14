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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
        const SizedBox(height: 12),
        Expanded(
          child: FractionallySizedBox(
            widthFactor: config.spectrumWidthFactor,
            heightFactor: config.spectrumHeightFactor,
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
        const SizedBox(height: 8),
      ],
    );
  }
}
