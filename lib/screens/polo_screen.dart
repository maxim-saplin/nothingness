import 'package:flutter/material.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/platform_channels.dart';
import '../widgets/retro_lcd_display.dart';
import '../widgets/skin_layout.dart';
import 'settings_screen.dart';

class PoloScreen extends StatefulWidget {
  final SongInfo? songInfo;
  final PoloScreenConfig config;
  final PlatformChannels platformChannels;
  final VoidCallback onToggleSettings;
  final bool isSettingsOpen;
  final SpectrumSettings settings;
  final ValueChanged<SpectrumSettings> onSettingsChanged;
  final bool debugLayout;

  const PoloScreen({
    super.key,
    required this.songInfo,
    required this.config,
    required this.platformChannels,
    required this.onToggleSettings,
    required this.isSettingsOpen,
    required this.settings,
    required this.onSettingsChanged,
    this.debugLayout = false,
  });

  @override
  State<PoloScreen> createState() => _PoloScreenState();
}

class _PoloScreenState extends State<PoloScreen> {
  @override
  Widget build(BuildContext context) {
    // Settings panel setup (similar to SpectrumScreen)
    const double panelWidth =
        350.0; // Fixed width for simplicity in this layout

    return Stack(
      children: [
        // Main Skin Content
        Scaffold(
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
            mediaControls: null, // No overlay controls for Polo skin
          ),
        ),

        // Settings Panel
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          top: 0,
          bottom: 0,
          right: widget.isSettingsOpen ? 0 : -panelWidth,
          width: panelWidth,
          child: SettingsScreen(
            settings: widget.settings,
            onSettingsChanged: widget.onSettingsChanged,
            // In Polo skin, we might not use UI scale, or we might pass a dummy/no-op
            uiScale: -1,
            onUiScaleChanged: (_) {},
            onClose: widget.onToggleSettings,
          ),
        ),
      ],
    );
  }
}
