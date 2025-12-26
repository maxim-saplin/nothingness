import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../providers/audio_player_provider.dart';
import '../widgets/media_button.dart';
import '../widgets/song_info_display.dart';
import '../widgets/spectrum_visualizer.dart';

class SpectrumScreen extends StatefulWidget {
  final SpectrumSettings settings;
  final SpectrumScreenConfig config;
  final VoidCallback onToggleSettings;
  final SongInfo? externalSongInfo;
  final List<double>? externalSpectrumData;

  const SpectrumScreen({
    super.key,
    required this.settings,
    required this.config,
    required this.onToggleSettings,
    this.externalSongInfo,
    this.externalSpectrumData,
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

  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerProvider>();
    final songInfo = widget.externalSongInfo ?? player.songInfo;
    final spectrumData = widget.externalSpectrumData ?? player.spectrumData;

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
                songInfo: songInfo,
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
                      data: spectrumData,
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
    final player = context.watch<AudioPlayerProvider>();
    final isPlaying = player.songInfo?.isPlaying ?? player.isPlaying;
    final scale = widget.config.mediaControlScale;
    final songInfo = player.songInfo;

    final position = _isDragging
        ? _dragValue
        : (songInfo?.position.toDouble() ?? 0.0);
    final duration = songInfo?.duration.toDouble() ?? 1.0;
    final max = duration > 0 ? duration : 1.0;
    final value = position.clamp(0.0, max);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FractionallySizedBox(
          widthFactor: widget.config.mediaSliderWidthFactor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Text(
                  _formatDuration(Duration(milliseconds: position.toInt())),
                  style: TextStyle(color: _textColor, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: value,
                    min: 0.0,
                    max: max,
                    activeColor: _mediaPrimary,
                    inactiveColor: _mediaSecondary.withValues(alpha: 0.3),
                    onChangeStart: (newValue) {
                      setState(() {
                        _isDragging = true;
                        _dragValue = newValue;
                      });
                    },
                    onChanged: (newValue) {
                      setState(() {
                        _dragValue = newValue;
                      });
                    },
                    onChangeEnd: (newValue) async {
                      await context.read<AudioPlayerProvider>().seek(
                            Duration(milliseconds: newValue.toInt()),
                          );
                      if (mounted) {
                        setState(() {
                          _isDragging = false;
                        });
                      }
                    },
                  ),
                ),
                Text(
                  _formatDuration(Duration(milliseconds: duration.toInt())),
                  style: TextStyle(color: _textColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16 * scale),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous button
            MediaButton(
              icon: Icons.skip_previous_rounded,
              size: 48 * scale,
              accentColor: _mediaSecondary,
              inactiveBackgroundColor: Colors.white.withAlpha(10),
              inactiveIconColor: Colors.white70,
              onTap: context.read<AudioPlayerProvider>().previous,
            ),
            SizedBox(width: 32 * scale),
            // Play/Pause button
            MediaButton(
              icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 72 * scale,
              isPrimary: true,
              accentColor: _mediaPrimary,
              onTap: context.read<AudioPlayerProvider>().playPause,
            ),
            SizedBox(width: 32 * scale),
            // Next button
            MediaButton(
              icon: Icons.skip_next_rounded,
              size: 48 * scale,
              accentColor: _mediaSecondary,
              inactiveBackgroundColor: Colors.white.withAlpha(10),
              inactiveIconColor: Colors.white70,
              onTap: context.read<AudioPlayerProvider>().next,
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}
