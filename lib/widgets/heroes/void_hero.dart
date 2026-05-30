import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../providers/audio_player_provider.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';

/// Track-metadata hero used by the `void` visualisation.
///
/// Pure visualisation — no transport widgets, no Scaffold, no AppBar.
/// Fills whatever box the hero slot gives it.
///
/// B-040 — renders a real two-level typographic hierarchy from the active
/// track's metadata instead of "track title + parent folder":
///   - **Artist** (H1) — the big mono headline (`track.artist`).
///   - **Song title** (H2) — a smaller secondary heading (`track.title`),
///     sized at [songSizeFactor]× the Artist size.
/// When the track has no parsed artist (e.g. a filename without a
/// `Artist - Title` separator) the song title takes the H1 slot and the
/// secondary line is omitted, so the hero never shows an empty headline.
/// With no track at all it falls back to the "nothingness" idle headline
/// plus the gesture hint.
///
/// The `isOneShot` / `shuffle` queue mode is surfaced as a `↩` / `≈` glyph
/// prefixed onto the secondary line (the song, or the lone title when there
/// is no artist) — the same affordance the old parent-folder subtitle had.
///
/// [config.textScale] (B-035) scales both heading levels together.
class VoidHero extends StatelessWidget {
  const VoidHero({super.key, this.config = const VoidScreenConfig()});

  final VoidScreenConfig config;

  /// B-040: the Song title (H2) renders at this fraction of the Artist (H1)
  /// size, giving a clear two-level hierarchy. Both levels still scale with
  /// [config.textScale] and the theme's `heroSize`.
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
        // No parsed artist — the song title carries the H1 slot so the hero
        // never renders an empty primary headline.
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

    return Container(
      width: double.infinity,
      // Horizontal padding is wide enough that the title text can never
      // reach the top-right `⋮` settings button (48 dp wide @ right: 4).
      padding: const EdgeInsets.fromLTRB(56, 12, 56, 12),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(
          bottom: BorderSide(color: palette.divider, width: 1),
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  /// Shared heading builder for the Artist / Song levels — same mono family,
  /// weight, and 2-line ellipsis treatment, differing only in size + colour.
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
