import 'package:flutter/material.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/platform_channels.dart';
import '../widgets/media_button.dart';
import '../widgets/song_info_display.dart';
import '../widgets/spectrum_visualizer.dart';

class SpectrumScreen extends StatefulWidget {
  final SongInfo? songInfo;
  final List<double> spectrumData;
  final SpectrumSettings settings;
  final SpectrumScreenConfig config;
  final PlatformChannels platformChannels;
  final VoidCallback onToggleSettings;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const SpectrumScreen({
    super.key,
    required this.songInfo,
    required this.spectrumData,
    required this.settings,
    required this.config,
    required this.platformChannels,
    required this.onToggleSettings,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<SpectrumScreen> createState() => _SpectrumScreenState();
}

class _SpectrumScreenState extends State<SpectrumScreen> {
  Color get _accentColor => widget.settings.colorScheme.colors.first;

  Color get _mediaPrimary => widget.config.mediaControlColorScheme.colors.first;
  Color get _mediaSecondary =>
      widget.config.mediaControlColorScheme.colors.length > 1
      ? widget.config.mediaControlColorScheme.colors[1]
      : widget.config.mediaControlColorScheme.colors.first;

  Color get _textColor => widget.config.textColorScheme.colors.first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(widget.config.textScale),
              ),
              child: SongInfoDisplay(
                songInfo: widget.songInfo,
                textColor: _textColor,
              ),
            ),
            const SizedBox(height: 40),
            // Spectrum visualizer
            Expanded(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: widget.config.spectrumWidthFactor,
                  heightFactor: widget.config.spectrumHeightFactor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SpectrumVisualizer(
                      data: widget.spectrumData,
                      settings: widget.settings,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            // Media controls
            if (widget.config.showMediaControls) _buildMediaControls(),
            const SizedBox(height: 20),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaControls() {
    final isPlaying = widget.songInfo?.isPlaying ?? false;
    final scale = widget.config.mediaControlScale;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous button
        MediaButton(
          icon: Icons.skip_previous_rounded,
          size: 48 * scale,
          accentColor: _mediaSecondary,
          inactiveBackgroundColor: Colors.white.withAlpha(10),
          inactiveIconColor: Colors.white70,
          onTap: widget.onPrevious,
        ),
        SizedBox(width: 32 * scale),
        // Play/Pause button
        MediaButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 72 * scale,
          isPrimary: true,
          accentColor: _mediaPrimary,
          onTap: widget.onPlayPause,
        ),
        SizedBox(width: 32 * scale),
        // Next button
        MediaButton(
          icon: Icons.skip_next_rounded,
          size: 48 * scale,
          accentColor: _mediaSecondary,
          inactiveBackgroundColor: Colors.white.withAlpha(10),
          inactiveIconColor: Colors.white70,
          onTap: widget.onNext,
        ),
      ],
    );
  }
}
