import 'package:flutter/material.dart';

import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../widgets/media_button.dart';
import '../widgets/scaled_layout.dart';
import '../widgets/song_info_display.dart';
import '../widgets/spectrum_visualizer.dart';
import 'settings_screen.dart';

class SpectrumScreen extends StatefulWidget {
  final SongInfo? songInfo;
  final List<double> spectrumData;
  final bool hasNotificationAccess;
  final bool hasAudioPermission;
  final SpectrumSettings settings;
  final PlatformChannels platformChannels;
  final VoidCallback onToggleSettings;
  final bool isSettingsOpen;
  final ValueChanged<SpectrumSettings> onSettingsChanged;

  const SpectrumScreen({
    super.key,
    required this.songInfo,
    required this.spectrumData,
    required this.hasNotificationAccess,
    required this.hasAudioPermission,
    required this.settings,
    required this.platformChannels,
    required this.onToggleSettings,
    required this.isSettingsOpen,
    required this.onSettingsChanged,
  });

  @override
  State<SpectrumScreen> createState() => _SpectrumScreenState();
}

class _SpectrumScreenState extends State<SpectrumScreen> {
  final _settingsService = SettingsService();

  Color get _accentColor => widget.settings.colorScheme.colors.first;
  Color get _accentColorSoft => widget.settings.colorScheme.colors.length > 1
      ? widget.settings.colorScheme.colors[1]
      : widget.settings.colorScheme.colors.first;

  // Get effective UI scale (default to 1.0 if auto/-1)
  double _uiScale = 1.0;

  @override
  void initState() {
    super.initState();
    _settingsService.uiScaleNotifier.addListener(_handleUiScaleChanged);
    _handleUiScaleChanged();
  }

  @override
  void dispose() {
    _settingsService.uiScaleNotifier.removeListener(_handleUiScaleChanged);
    super.dispose();
  }

  void _handleUiScaleChanged() {
    final rawScale = _settingsService.uiScaleNotifier.value;
    if (mounted) {
      setState(() {
        _uiScale = rawScale > 0 ? rawScale : 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine panel width logic
    final screenWidth = MediaQuery.of(context).size.width;

    // Calculate panel width based on the logical scaled width
    final logicalScreenWidth = screenWidth / _uiScale;
    final panelWidth = logicalScreenWidth > 900
        ? logicalScreenWidth / 3
        : (logicalScreenWidth / 2).clamp(300.0, 400.0);

    return ScaledLayout(
      child: Stack(
        children: [
          // Main Content
          Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                IconButton(
                  icon: Icon(Icons.more_vert, color: _accentColor),
                  onPressed: widget.onToggleSettings,
                ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Song info section
                  SongInfoDisplay(
                    songInfo: widget.songInfo,
                    hasNotificationAccess: widget.hasNotificationAccess,
                    isAndroid: PlatformChannels.isAndroid,
                  ),
                  const SizedBox(height: 40),
                  // Spectrum visualizer
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SpectrumVisualizer(
                        data: widget.spectrumData,
                        settings: widget.settings,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Media controls
                  _buildMediaControls(),
                  const SizedBox(height: 20),
                  // Permission buttons (if needed)
                  if (PlatformChannels.isAndroid) _buildPermissionButtons(),
                  const SizedBox(height: 40),
                ],
              ),
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
              uiScale: _settingsService.uiScaleNotifier.value,
              onUiScaleChanged: (scale) => _settingsService.saveUiScale(scale),
              onClose: widget.onToggleSettings,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaControls() {
    final isPlaying = widget.songInfo?.isPlaying ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous button
        MediaButton(
          icon: Icons.skip_previous_rounded,
          size: 48,
          accentColor: _accentColorSoft,
          inactiveBackgroundColor: Colors.white.withAlpha(10),
          inactiveIconColor: Colors.white70,
          onTap: widget.platformChannels.previous,
        ),
        const SizedBox(width: 32),
        // Play/Pause button
        MediaButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 72,
          isPrimary: true,
          accentColor: _accentColor,
          onTap: widget.platformChannels.playPause,
        ),
        const SizedBox(width: 32),
        // Next button
        MediaButton(
          icon: Icons.skip_next_rounded,
          size: 48,
          accentColor: _accentColorSoft,
          inactiveBackgroundColor: Colors.white.withAlpha(10),
          inactiveIconColor: Colors.white70,
          onTap: widget.platformChannels.next,
        ),
      ],
    );
  }

  Widget _buildPermissionButtons() {
    final buttons = <Widget>[];

    if (!widget.hasNotificationAccess) {
      buttons.add(
        TextButton.icon(
          onPressed: widget.platformChannels.openNotificationSettings,
          icon: const Icon(Icons.settings, size: 18),
          label: const Text('Enable Notification Access'),
          style: TextButton.styleFrom(foregroundColor: _accentColor),
        ),
      );
    }

    if (!widget.hasAudioPermission) {
      buttons.add(
        TextButton.icon(
          onPressed: widget.platformChannels.requestAudioPermission,
          icon: const Icon(Icons.mic, size: 18),
          label: const Text('Enable Microphone'),
          style: TextButton.styleFrom(foregroundColor: _accentColorSoft),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: buttons,
      ),
    );
  }
}

