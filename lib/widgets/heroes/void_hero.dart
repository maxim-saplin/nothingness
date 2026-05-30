import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../providers/audio_player_provider.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';
import 'base_hero_container.dart';

/// Track-metadata hero for the `void` visualisation — pure visual, fills the hero slot.
///
/// B-040 — two-level typographic hierarchy from the track metadata: Artist (H1, big mono headline) and Song title (H2, at [songSizeFactor]× the H1 size). With no parsed artist the song title takes the H1 slot and H2 is omitted; with no track it falls back to the "nothingness" idle headline plus a gesture hint. The `isOneShot` / `shuffle` queue mode prefixes a `↩` / `≈` glyph onto the secondary (or lone) line. [config.textScale] (B-035) scales both levels together.
class VoidHero extends StatelessWidget {
  const VoidHero({super.key, this.config = const VoidScreenConfig()});

  final VoidScreenConfig config;

  /// B-040: the Song title (H2) renders at this fraction of the Artist (H1) size.
  static const double songSizeFactor = 0.5;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final player = context.watch<AudioPlayerProvider>();
    final track = player.songInfo?.track;
    final hasTrack = track != null;

    final h1Size = typography.heroSize * config.textScale;
    final h2Size = typography.heroSize * songSizeFactor * config.textScale;

    final List<Widget> children;
    if (!hasTrack) {
      children = [
        _heading(
          'nothingness',
          key: const ValueKey('void-hero-artist'),
          color: palette.fgPrimary,
          typography: typography,
          fontSize: h1Size,
        ),
        const SizedBox(height: 12),
        Flexible(
          child: Text(
            'long-press a folder · ←→ skip · settings ↗',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.fgTertiary,
              fontFamily: typography.monoFamily,
              fontSize: typography.hintSize * config.textScale,
              letterSpacing: 0.18,
            ),
          ),
        ),
      ];
    } else {
      final artist = track.artist.trim();
      final hasArtist = artist.isNotEmpty;
      final modeGlyph = player.isOneShot
          ? '↩ '
          : player.shuffle
              ? '≈ '
              : '';
      if (hasArtist) {
        children = [
          // Artist — H1 (primary headline).
          _heading(
            artist,
            key: const ValueKey('void-hero-artist'),
            color: palette.fgPrimary,
            typography: typography,
            fontSize: h1Size,
          ),
          const SizedBox(height: 8),
          // Song title — H2 (secondary heading).
          _heading(
            '$modeGlyph${track.title}',
            key: const ValueKey('void-hero-song'),
            color: palette.fgSecondary,
            typography: typography,
            fontSize: h2Size,
          ),
        ];
      } else {
        // No parsed artist — the song title carries the H1 slot.
        children = [
          _heading(
            '$modeGlyph${track.title}',
            key: const ValueKey('void-hero-song'),
            color: palette.fgPrimary,
            typography: typography,
            fontSize: h1Size,
          ),
        ];
      }
    }

    return BaseHeroContainer(
      width: double.infinity,
      // Horizontal padding keeps the title clear of the top-right `⋮` settings button (48 dp wide @ right: 4).
      padding: const EdgeInsets.fromLTRB(56, 12, 56, 12),
      showDivider: true,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  /// Shared heading builder for the Artist / Song levels — same mono / 2-line ellipsis treatment, differing only in size + colour.
  Widget _heading(
    String text, {
    required Key key,
    required Color color,
    required AppTypography typography,
    required double fontSize,
  }) {
    return Flexible(
      child: Text(
        text,
        key: key,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontFamily: typography.monoFamily,
          fontSize: fontSize,
          letterSpacing: typography.heroLetterSpacing,
          fontWeight: FontWeight.w300,
          height: 1.18,
        ),
      ),
    );
  }
}
