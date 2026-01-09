import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../providers/audio_player_provider.dart';

class DotScreen extends StatefulWidget {
  final SpectrumSettings settings;
  final DotScreenConfig config;
  final VoidCallback onToggleSettings;
  final SongInfo? externalSongInfo;
  final List<double>? externalSpectrumData;

  const DotScreen({
    super.key,
    required this.settings,
    required this.config,
    required this.onToggleSettings,
    this.externalSongInfo,
    this.externalSpectrumData,
  });

  @override
  State<DotScreen> createState() => _DotScreenState();
}

class _DotScreenState extends State<DotScreen> {
  double _calculateDotRadius(List<double> spectrumData) {
    if (spectrumData.isEmpty) return widget.config.minDotSize;

    // Use max of bass frequencies (first 3 bins) for punchier response
    double bassEnergy = 0.0;
    final bassBuckets = min(spectrumData.length, 3);
    for (int i = 0; i < bassBuckets; i++) {
      bassEnergy = max(bassEnergy, spectrumData[i]);
    }

    // Square the energy to exaggerate peaks (make the beat "pop")
    final energy = bassEnergy * bassEnergy;

    final minRadius = widget.config.minDotSize;
    final maxRadius = widget.config.maxDotSize;
    final sensitivity = widget.config.sensitivity;

    return (minRadius + (energy * sensitivity * (maxRadius - minRadius))).clamp(
      minRadius,
      maxRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerProvider>();
    final spectrumData = widget.externalSpectrumData ?? player.spectrumData;
    final songInfo = widget.externalSongInfo ?? player.songInfo;

    final dotRadius = _calculateDotRadius(spectrumData);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: widget.onToggleSettings,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenSize = MediaQuery.of(context).size;
          final screenWidth = screenSize.width;
          final screenHeight = screenSize.height;

          // Center circle: 30% of smaller dimension
          final centerDiameter = min(screenWidth, screenHeight) * 0.3;

          // Bottom rectangles: 40% width, 15% height
          final bottomButtonWidth = screenWidth * 0.4;
          final bottomButtonHeight = screenHeight * 0.15;
          final bottomPadding = 106.0; // Small padding from edge

          return Stack(
            children: [
              // Fluctuating Dot (Centered)
              Center(
                child: Container(
                  width: dotRadius * 2,
                  height: dotRadius * 2,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: widget.config.dotOpacity,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              // Song Title (Lower bottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: screenHeight / 9,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    songInfo?.title ?? 'Nothing playing',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(
                        alpha: widget.config.textOpacity,
                      ),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),

              // Center Play/Pause Button (Circular)
              Positioned(
                left: (screenWidth - centerDiameter) / 2,
                top: (screenHeight - centerDiameter) / 2,
                width: centerDiameter,
                height: centerDiameter,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: player.playPause,
                    customBorder: const CircleBorder(),
                    splashColor: Colors.white.withValues(alpha: 0.3),
                    highlightColor: Colors.white.withValues(alpha: 0.1),
                    child: Container(),
                  ),
                ),
              ),

              // Bottom Left Previous Button (Rectangular)
              Positioned(
                left: bottomPadding,
                bottom: bottomPadding,
                width: bottomButtonWidth,
                height: bottomButtonHeight,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: player.previous,
                    customBorder: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    splashColor: Colors.white.withValues(alpha: 0.3),
                    highlightColor: Colors.white.withValues(alpha: 0.1),
                    child: Container(),
                  ),
                ),
              ),

              // Bottom Right Next Button (Rectangular)
              Positioned(
                right: bottomPadding,
                bottom: bottomPadding,
                width: bottomButtonWidth,
                height: bottomButtonHeight,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: player.next,
                    customBorder: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    splashColor: Colors.white.withValues(alpha: 0.3),
                    highlightColor: Colors.white.withValues(alpha: 0.1),
                    child: Container(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
