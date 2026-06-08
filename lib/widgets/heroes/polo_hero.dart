import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/screen_config.dart';
import '../../models/song_info.dart';
import '../../services/playback_controller.dart';
import '../retro_lcd_display.dart';
import '../skin_layout.dart';
import 'base_hero_container.dart';

/// Polo visualisation embedded in the Void hero slot. SkinLayout is fit-contained so the source image keeps its aspect ratio (letterbox bands when the box doesn't match); tap regions stay live — Polo's transport is part of the image, not the chrome.
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final songInfo =
        context.select<PlaybackController, SongInfo?>((player) => player.songInfo);
    final transport = context.read<PlaybackController>();

    // SkinLayout assumes a 1080×~2400 aspect; FittedBox(contain) letterboxes it while staying tappable (hit-testing propagates through the inner rects).
    final Widget skin = SizedBox(
      width: 1080,
      height: 2400,
      child: SkinLayout(
        backgroundImagePath: config.backgroundImagePath,
        lcdRect: config.lcdRect,
        debugLayout: debugLayout,
        lcdContent: RetroLcdDisplay(
          songInfo: songInfo,
          fontFamily: config.fontFamily,
          textColor: config.textColor,
          textScale: config.textScale,
        ),
        controlAreas: [
          SkinControlArea(
            rect: config.prevRect,
            shape: SkinControlShape.rectangle,
            onTap: transport.previous,
            debugLabel: 'Prev',
          ),
          SkinControlArea(
            rect: config.playPauseRect,
            shape: SkinControlShape.circle,
            onTap: transport.playPause,
            debugLabel: 'Play/Pause',
          ),
          SkinControlArea(
            rect: config.nextRect,
            shape: SkinControlShape.rectangle,
            onTap: transport.next,
            debugLabel: 'Next',
          ),
        ],
        mediaControls: null,
      ),
    );

    return BaseHeroContainer(
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.contain,
        child: isLight
            ? ColorFiltered(colorFilter: _invertFilter, child: skin)
            : skin,
      ),
    );
  }
}
