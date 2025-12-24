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

    double sum = 0;
    int count = 0;
    final bassBuckets = min(spectrumData.length, 8);
    for (int i = 0; i < bassBuckets; i++) {
      sum += spectrumData[i];
      count++;
    }

    final average = count > 0 ? sum / count : 0.0;

    final minRadius = widget.config.minDotSize;
    final maxRadius = widget.config.maxDotSize;
    final sensitivity = widget.config.sensitivity;

    return (minRadius + (average * sensitivity * (maxRadius - minRadius)))
        .clamp(minRadius, maxRadius);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerProvider>();
    final spectrumData = widget.externalSpectrumData ?? player.spectrumData;
    final songInfo = widget.externalSongInfo ?? player.songInfo;

    final dotRadius = _calculateDotRadius(spectrumData);

    return Scaffold(
      backgroundColor: Colors.black,
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
      body: Stack(
        children: [
          // Fluctuating Dot (Centered)
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: dotRadius * 2,
              height: dotRadius * 2,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: widget.config.dotOpacity),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Song Title (Lower bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).size.height / 9,
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
        ],
      ),
    );
  }
}
