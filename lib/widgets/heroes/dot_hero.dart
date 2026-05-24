import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../providers/audio_player_provider.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';

/// Dot visualisation embedded in the Void hero slot.
///
/// A single pulsing circle whose radius tracks the bass energy of the
/// spectrum stream. The Void chrome owns transport gestures and the
/// transport row, so this is purely the visual — no in-screen tap
/// zones, no title row by default (the dot is identity enough).
///
/// When [DotScreenConfig.showSongInfo] is `true` (opt-in via the
/// DISPLAY group of settings — B-020), the hero overlays the active
/// track's title and parent folder at the top of the hero band, using
/// the same mono / `fgPrimary` typography Spectrum and Void apply.
/// The overlay is painted in a [Stack] above the centered dot so it
/// never reflows the dot's position.
///
/// Scales naturally to whatever size the hero slot gives it: the dot
/// is clamped to a fraction of the smallest dimension so it never
/// overflows even at hero-slot heights of ~32 % viewport.
class DotHero extends StatelessWidget {
  const DotHero({
    super.key,
    required this.config,
  });

  final DotScreenConfig config;

  double _radiusFor(List<double> spectrum, double maxAllowed) {
    if (spectrum.isEmpty) return min(config.minDotSize, maxAllowed);
    double bass = 0.0;
    final n = min(spectrum.length, 3);
    for (int i = 0; i < n; i++) {
      bass = max(bass, spectrum[i]);
    }
    final energy = bass * bass;
    final r = config.minDotSize +
        energy * config.sensitivity * (config.maxDotSize - config.minDotSize);
    return r.clamp(config.minDotSize, min(config.maxDotSize, maxAllowed));
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final player = context.watch<AudioPlayerProvider>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxAllowed = min(constraints.maxWidth, constraints.maxHeight) / 2;
        final r = _radiusFor(player.spectrumData, maxAllowed);
        return Container(
          color: palette.background,
          child: Stack(
            children: [
              // Pulsing dot — always centered.
              Center(
                child: Container(
                  width: r * 2,
                  height: r * 2,
                  decoration: BoxDecoration(
                    color: palette.fgPrimary.withValues(alpha: config.dotOpacity),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Optional song-info overlay pinned to the top of the hero band
              // (B-020). Lives above the dot so transport-row at the bottom
              // never collides with the metadata.
              if (config.showSongInfo)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 12,
                  child: _DotSongInfo(opacity: config.textOpacity),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Title + parent-folder overlay used by [DotHero] when
/// `DotScreenConfig.showSongInfo` is true.
///
/// Mirrors the typography Spectrum and Void use for their title block so
/// the three hosted heroes share a single visual language for the
/// currently-playing track. Reads the active track from
/// [AudioPlayerProvider]; falls back to the "nothingness" idle headline
/// when no track is loaded (matches [VoidHero]'s idle treatment).
class _DotSongInfo extends StatelessWidget {
  const _DotSongInfo({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final player = context.watch<AudioPlayerProvider>();
    final track = player.songInfo?.track;
    final hasTrack = track != null;
    final parent = hasTrack && track.path.isNotEmpty
        ? p.basename(p.dirname(track.path))
        : '';

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Padding(
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
    );
  }
}
