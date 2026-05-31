import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../services/playback_controller.dart';
import '../../theme/app_palette.dart';
import 'base_hero_container.dart';
import 'hero_title_block.dart';

/// Dot visualisation embedded in the Void hero slot: a single pulsing circle whose radius tracks the spectrum's bass energy (Void chrome owns transport). When [DotScreenConfig.showSongInfo] is true (B-020) the active track's Artist (H1) / Song (H2) overlay the top of the band in a [Stack] above the centered dot, using the shared [HeroTitleBlock] (B-046). The dot is clamped to a fraction of the smallest dimension so it never overflows.
class DotHero extends StatelessWidget {
  const DotHero({super.key, required this.config});

  final DotScreenConfig config;

  double _radiusFor(List<double> spectrum, double maxAllowed) {
    if (spectrum.isEmpty) return min(config.minDotSize, maxAllowed);
    var bass = 0.0;
    for (var i = 0; i < min(spectrum.length, 3); i++) {
      bass = max(bass, spectrum[i]);
    }
    final r = config.minDotSize +
        bass * bass * config.sensitivity * (config.maxDotSize - config.minDotSize);
    return r.clamp(config.minDotSize, min(config.maxDotSize, maxAllowed));
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final player = context.watch<PlaybackController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxAllowed = min(constraints.maxWidth, constraints.maxHeight) / 2;
        final r = _radiusFor(player.spectrumData, maxAllowed);
        return BaseHeroContainer(
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
              // Optional song-info overlay pinned to the top of the hero band (B-020), above the dot.
              if (config.showSongInfo)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 12,
                  child: Opacity(
                    opacity: config.textOpacity.clamp(0.0, 1.0),
                    child: HeroTitleBlock(textScale: config.textScale),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
