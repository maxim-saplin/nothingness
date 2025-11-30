import 'package:flutter/material.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/platform_channels.dart';
import '../widgets/retro_lcd_display.dart';
import '../widgets/skin_layout.dart';

class PoloScreen extends StatefulWidget {
  final SongInfo? songInfo;
  final PoloScreenConfig config;
  final PlatformChannels platformChannels;
  final VoidCallback onToggleSettings;
  final SpectrumSettings settings;
  final bool debugLayout;

  const PoloScreen({
    super.key,
    required this.songInfo,
    required this.config,
    required this.platformChannels,
    required this.onToggleSettings,
    required this.settings,
    this.debugLayout = false,
  });

  @override
  State<PoloScreen> createState() => _PoloScreenState();
}

class _PoloScreenState extends State<PoloScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const SizedBox(), // Hide back button if any
        actions: [
          IconButton(
            icon: Icon(
              Icons.more_vert,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            onPressed: widget.onToggleSettings,
          ),
        ],
      ),
      body: SkinLayout(
        backgroundImagePath: widget.config.backgroundImagePath,
        lcdRect: widget.config.lcdRect,
        debugLayout: widget.debugLayout,
        lcdContent: RetroLcdDisplay(
          songInfo: widget.songInfo,
          fontFamily: widget.config.fontFamily,
          textColor: widget.config.textColor,
        ),
        controlAreas: [
          // Previous Button
          SkinControlArea(
            rect: widget.config.prevRect,
            shape: SkinControlShape.rectangle,
            onTap: widget.platformChannels.previous,
            debugLabel: 'Prev',
          ),
          // Play/Pause Button
          SkinControlArea(
            rect: widget.config.playPauseRect,
            shape: SkinControlShape.circle,
            onTap: widget.platformChannels.playPause,
            debugLabel: 'Play/Pause',
          ),
          // Next Button
          SkinControlArea(
            rect: widget.config.nextRect,
            shape: SkinControlShape.rectangle,
            onTap: widget.platformChannels.next,
            debugLabel: 'Next',
          ),
        ],
        mediaControls: null, // No overlay controls for Polo skin
      ),
    );
  }
}
