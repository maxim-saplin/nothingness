import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../services/playback_controller.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';

/// Mono headline [TextStyle] shared by [HeroTitleBlock] and `VoidHero` — the
/// two-line hero title treatment (`fgPrimary`-style colour, `monoFamily`, w300,
/// 1.18 line height, `heroLetterSpacing`). Differs only in size + colour.
TextStyle heroHeadingStyle(
  AppTypography typography, {
  required Color color,
  required double fontSize,
}) =>
    TextStyle(
      color: color,
      fontFamily: typography.monoFamily,
      fontSize: fontSize,
      letterSpacing: typography.heroLetterSpacing,
      fontWeight: FontWeight.w300,
      height: 1.18,
    );

/// Shared title + parent-folder block used by [HeroTitleBlock]'s hosts (DotHero,
/// SpectrumHero). Title in mono / `fgPrimary` at `heroSize * textScale`; optional
/// parent-folder crumb in `fgTertiary` at `hintSize * textScale`. Falls back to
/// the "nothingness" idle headline with no track. Reads the active track from
/// [PlaybackController]. [textScale] (B-035) scales both lines.
class HeroTitleBlock extends StatelessWidget {
  const HeroTitleBlock({super.key, this.textScale = 1.0});

  final double textScale;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final track = context.watch<PlaybackController>().songInfo?.track;
    final hasTrack = track != null;
    final parent = hasTrack && track.path.isNotEmpty
        ? p.basename(p.dirname(track.path))
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasTrack ? track.title : 'nothingness',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: heroHeadingStyle(
              typography,
              color: palette.fgPrimary,
              fontSize: typography.heroSize * textScale,
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
                fontSize: typography.hintSize * textScale,
                letterSpacing: 0.18,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
