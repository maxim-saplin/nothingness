import 'dart:math';

import 'package:flutter/material.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';

class DotScreen extends StatefulWidget {
  final SongInfo? songInfo;
  final List<double> spectrumData;
  final SpectrumSettings settings;
  final DotScreenConfig config;
  final VoidCallback onToggleSettings;

  const DotScreen({
    super.key,
    required this.songInfo,
    required this.spectrumData,
    required this.settings,
    required this.config,
    required this.onToggleSettings,
  });

  @override
  State<DotScreen> createState() => _DotScreenState();
}

class _DotScreenState extends State<DotScreen> {
  double _calculateDotRadius() {
    if (widget.spectrumData.isEmpty) return widget.config.minDotSize;

    // Calculate average amplitude
    double sum = 0;
    int count = 0;
    // Focus on bass frequencies (first few buckets) for better "beat" feel
    final bassBuckets = min(widget.spectrumData.length, 8);
    for (int i = 0; i < bassBuckets; i++) {
      sum += widget.spectrumData[i];
      count++;
    }

    final average = count > 0 ? sum / count : 0.0;

    // Map amplitude (0.0 - 1.0 usually, but can be higher depending on normalization)
    // to a radius range. Base radius 20, max radius 100.
    final minRadius = widget.config.minDotSize;
    final maxRadius = widget.config.maxDotSize;

    // Apply sensitivity (simple multiplier for now)
    final sensitivity = widget.config.sensitivity;

    return (minRadius + (average * sensitivity * (maxRadius - minRadius)))
        .clamp(minRadius, maxRadius);
  }

  @override
  Widget build(BuildContext context) {
    final dotRadius = _calculateDotRadius();

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
                widget.songInfo?.title ?? 'Nothing playing',
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
