import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../providers/audio_player_provider.dart';
import '../../theme/app_palette.dart';
import '../retro_lcd_display.dart';
import '../skin_layout.dart';

/// Polo visualisation embedded in the Void hero slot.
///
/// SkinLayout is fit-contained inside the hero box so the source image
/// preserves its aspect ratio (letterbox / pillarbox bands where the
/// hero box doesn't match). Tap regions stay live — Polo's transport
/// is part of the image, not the chrome.
class PoloHero extends StatelessWidget {
  const PoloHero({
    super.key,
    required this.config,
    this.debugLayout = false,
  });

  final PoloScreenConfig config;
  final bool debugLayout;

  static const ColorFilter _invertFilter = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final isLight = theme.brightness == Brightness.light;
    final player = context.watch<AudioPlayerProvider>();

    // SkinLayout assumes a 1080×~2400 aspect; FittedBox(contain) inside a
    // sized parent gives it natural letterboxing while staying tappable
    // (the FittedBox propagates hit-testing through the inner rects).
    final Widget skin = SizedBox(
      width: 1080,
      height: 2400,
      child: SkinLayout(
        backgroundImagePath: config.backgroundImagePath,
        lcdRect: config.lcdRect,
        debugLayout: debugLayout,
        lcdContent: RetroLcdDisplay(
          songInfo: player.songInfo,
          fontFamily: config.fontFamily,
          textColor: config.textColor,
        ),
        controlAreas: [
          SkinControlArea(
            rect: config.prevRect,
            shape: SkinControlShape.rectangle,
            onTap: context.read<AudioPlayerProvider>().previous,
            debugLabel: 'Prev',
          ),
          SkinControlArea(
            rect: config.playPauseRect,
            shape: SkinControlShape.circle,
            onTap: context.read<AudioPlayerProvider>().playPause,
            debugLabel: 'Play/Pause',
          ),
          SkinControlArea(
            rect: config.nextRect,
            shape: SkinControlShape.rectangle,
            onTap: context.read<AudioPlayerProvider>().next,
            debugLabel: 'Next',
          ),
        ],
        mediaControls: null,
      ),
    );

    final Widget body = isLight
        ? ColorFiltered(colorFilter: _invertFilter, child: skin)
        : skin;

    return Container(
      color: palette.background,
      alignment: Alignment.center,
      child: FittedBox(fit: BoxFit.contain, child: body),
    );
  }
}
