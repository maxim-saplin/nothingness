import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/playback_controller.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';

/// Song title (H2) size as a fraction of the Artist (H1) size.
const double heroSongSizeFactor = 0.5;

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

/// Two-level hero title shared by Void, Spectrum and Dot: Artist (H1) over Song
/// (H2), scaled by [textScale]. No artist → the song takes the H1 slot; no track
/// → the "nothingness" idle headline, plus a gesture hint when [showIdleHint]. A
/// `↩`/`≈` glyph marks one-shot / shuffle on the lower line.
class HeroTitleBlock extends StatelessWidget {
  const HeroTitleBlock({
    super.key,
    this.textScale = 1.0,
    this.showIdleHint = false,
  });

  final double textScale;
  final bool showIdleHint;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final player = context.watch<PlaybackController>();
    final track = player.songInfo?.track;

    final h1Size = typography.heroSize * textScale;
    final h2Size = typography.heroSize * heroSongSizeFactor * textScale;

    Widget heading(String text,
            {required Key key,
            required Color color,
            required double fontSize}) =>
        Text(
          text,
          key: key,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: heroHeadingStyle(typography, color: color, fontSize: fontSize),
        );

    final List<Widget> children;
    if (track == null) {
      children = [
        heading('nothingness',
            key: const ValueKey('hero-artist'),
            color: palette.fgPrimary,
            fontSize: h1Size),
        if (showIdleHint) ...[
          const SizedBox(height: 12),
          Text(
            'long-press a folder · ←→ skip · settings ↗',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.fgTertiary,
              fontFamily: typography.monoFamily,
              fontSize: typography.hintSize * textScale,
              letterSpacing: 0.18,
            ),
          ),
        ],
      ];
    } else {
      final artist = track.artist.trim();
      final glyph = player.isOneShot
          ? '↩ '
          : player.shuffle
              ? '≈ '
              : '';
      final song = heading('$glyph${track.title}',
          key: const ValueKey('hero-song'),
          color: artist.isEmpty ? palette.fgPrimary : palette.fgSecondary,
          fontSize: artist.isEmpty ? h1Size : h2Size);
      children = artist.isEmpty
          ? [song]
          : [
              heading(artist,
                  key: const ValueKey('hero-artist'),
                  color: palette.fgPrimary,
                  fontSize: h1Size),
              const SizedBox(height: 8),
              song,
            ];
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }
}
