import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../providers/audio_player_provider.dart';
import '../widgets/retro_lcd_display.dart';
import '../widgets/skin_layout.dart';

class PoloScreen extends StatefulWidget {
  final PoloScreenConfig config;
  final VoidCallback onToggleSettings;
  final SpectrumSettings settings;
  final bool debugLayout;
  final SongInfo? externalSongInfo;

  const PoloScreen({
    super.key,
    required this.config,
    required this.onToggleSettings,
    required this.settings,
    this.debugLayout = false,
    this.externalSongInfo,
  });

  @override
  State<PoloScreen> createState() => _PoloScreenState();
}

class _PoloScreenState extends State<PoloScreen> {
  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerProvider>();
    final songInfo = widget.externalSongInfo ?? player.songInfo;

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
          songInfo: songInfo,
          fontFamily: widget.config.fontFamily,
          textColor: widget.config.textColor,
        ),
        controlAreas: [
          // Previous Button
          SkinControlArea(
            rect: widget.config.prevRect,
            shape: SkinControlShape.rectangle,
            onTap: context.read<AudioPlayerProvider>().previous,
            debugLabel: 'Prev',
          ),
          // Play/Pause Button
          SkinControlArea(
            rect: widget.config.playPauseRect,
            shape: SkinControlShape.circle,
            onTap: context.read<AudioPlayerProvider>().playPause,
            debugLabel: 'Play/Pause',
          ),
          // Next Button
          SkinControlArea(
            rect: widget.config.nextRect,
            shape: SkinControlShape.rectangle,
            onTap: context.read<AudioPlayerProvider>().next,
            debugLabel: 'Next',
          ),
        ],
        mediaControls: null, // No overlay controls for Polo skin
      ),
    );
  }
}
