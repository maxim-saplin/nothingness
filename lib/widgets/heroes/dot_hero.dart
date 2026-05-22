import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../providers/audio_player_provider.dart';
import '../../theme/app_palette.dart';

/// Dot visualisation embedded in the Void hero slot.
///
/// A single pulsing circle whose radius tracks the bass energy of the
/// spectrum stream. The Void chrome owns transport gestures and the
/// transport row, so this is purely the visual — no in-screen tap
/// zones, no title row (the hero box owns that via the void hero when
/// the user wants a textual fallback; the dot is identity enough).
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
          alignment: Alignment.center,
          child: Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              color: palette.fgPrimary.withValues(alpha: config.dotOpacity),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
