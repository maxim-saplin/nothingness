import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../providers/audio_player_provider.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_typography.dart';

/// Track-title hero used by the `void` visualisation.
///
/// Pure visualisation — no transport widgets, no Scaffold, no AppBar.
/// Fills whatever box the hero slot gives it; the title flexes, the
/// subtitle stays a single line.
///
/// Inputs come from the active `AudioPlayerProvider`:
///   - `songInfo.track.title` → big mono headline (or "nothingness" idle).
///   - `songInfo.track.path`  → parent folder name for the subtitle.
///   - `isOneShot` / `shuffle` → subtitle decoration (`↩` / `≈`).
class VoidHero extends StatelessWidget {
  const VoidHero({super.key});

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

    final String subtitle;
    if (!hasTrack) {
      subtitle = 'long-press a folder · ←→ skip · settings ↗';
    } else if (player.isOneShot) {
      subtitle = '↩ $parent';
    } else if (player.shuffle) {
      subtitle = '≈ $parent';
    } else {
      subtitle = parent;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
        children: [
          Flexible(
            child: Text(
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
          ),
          const SizedBox(height: 12),
          Flexible(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.fgTertiary,
                fontFamily: typography.monoFamily,
                fontSize: typography.hintSize,
                letterSpacing: 0.18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
