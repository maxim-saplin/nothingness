import 'dart:math';

import 'package:flutter/material.dart';

import '../models/spectrum_settings.dart';

class SpectrumVisualizer extends StatelessWidget {
  final List<double> data;
  final SpectrumSettings settings;

  const SpectrumVisualizer({
    super.key,
    required this.data,
    required this.settings,
  });

  // Frequency labels for display (logarithmic distribution)
  static const List<String> _frequencyLabels8 = [
    '60',
    '150',
    '400',
    '1k',
    '2.5k',
    '6k',
    '10k',
    '16k',
  ];
  static const List<String> _frequencyLabels12 = [
    '60',
    '100',
    '200',
    '400',
    '800',
    '1.5k',
    '3k',
    '5k',
    '8k',
    '11k',
    '14k',
    '16k',
  ];
  static const List<String> _frequencyLabels24 = [
    '31',
    '50',
    '70',
    '100',
    '140',
    '200',
    '280',
    '400',
    '560',
    '800',
    '1.1k',
    '1.6k',
    '2.2k',
    '3k',
    '4k',
    '5.5k',
    '7k',
    '9k',
    '11k',
    '13k',
    '14k',
    '15k',
    '16k',
    '18k',
  ];

  List<String> get _labels {
    switch (settings.barCount) {
      case BarCount.bars8:
        return _frequencyLabels8;
      case BarCount.bars12:
        return _frequencyLabels12;
      case BarCount.bars24:
        return _frequencyLabels24;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Resample data to match bar count
    final targetCount = settings.barCount.count;
    final resampledData = _resampleData(data, targetCount);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Spectrum bars (centered, not stretched)
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _calculateVisualizerWidth(targetCount),
              ),
              child: CustomPaint(
                painter: _SpectrumPainter(
                  data: resampledData,
                  settings: settings,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Frequency labels
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _calculateVisualizerWidth(targetCount),
            ),
            child: _buildFrequencyLabels(targetCount),
          ),
        ),
      ],
    );
  }

  double _calculateVisualizerWidth(int barCount) {
    // Fixed width per bar for consistent sizing
    const barWidth = 24.0;
    const gapRatio = 0.4;
    return barCount * barWidth * (1 + gapRatio);
  }

  Widget _buildFrequencyLabels(int barCount) {
    final labels = _labels;
    // Show fewer labels for readability
    final showEvery = barCount == 24 ? 3 : (barCount == 12 ? 2 : 1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(barCount, (i) {
        final showLabel = i % showEvery == 0 || i == barCount - 1;
        return SizedBox(
          width: _calculateVisualizerWidth(barCount) / barCount,
          child: Text(
            showLabel ? labels[i] : '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white38,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }),
    );
  }

  List<double> _resampleData(List<double> source, int targetCount) {
    if (source.isEmpty) return List.filled(targetCount, 0.0);
    if (source.length == targetCount) return source;

    final result = <double>[];
    final ratio = source.length / targetCount;

    for (int i = 0; i < targetCount; i++) {
      final start = (i * ratio).floor();
      final end = ((i + 1) * ratio).floor().clamp(start + 1, source.length);

      // Take max value in the range for better visual response
      double maxVal = 0.0;
      for (int j = start; j < end; j++) {
        if (source[j] > maxVal) maxVal = source[j];
      }
      result.add(maxVal);
    }

    return result;
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> data;
  final SpectrumSettings settings;

  _SpectrumPainter({required this.data, required this.settings});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final barCount = data.length;
    final totalWidth = size.width;
    final barWidth = (totalWidth / barCount) * 0.65;
    final gap = (totalWidth / barCount) * 0.35;
    final maxBarHeight = size.height;

    // Number of segments for 80s style (pixelated look)
    const segmentCount = 16;
    final segmentHeight = maxBarHeight / segmentCount;
    final segmentGap = segmentHeight * 0.15;
    final actualSegmentHeight = segmentHeight - segmentGap;

    for (int i = 0; i < barCount; i++) {
      final barHeight = data[i] * maxBarHeight;
      final x = i * (barWidth + gap) + gap / 2;

      // Calculate how many segments to light up
      final litSegments = (barHeight / segmentHeight).ceil().clamp(
        0,
        segmentCount,
      );

      switch (settings.barStyle) {
        case BarStyle.segmented:
          _drawSegmentedBar(
            canvas,
            x,
            size.height,
            barWidth,
            litSegments,
            segmentCount,
            actualSegmentHeight,
            segmentHeight,
          );
          break;
        case BarStyle.solid:
          _drawSolidBar(
            canvas,
            x,
            size.height,
            barWidth,
            barHeight,
            maxBarHeight,
          );
          break;
        case BarStyle.glow:
          _drawGlowBar(
            canvas,
            x,
            size.height,
            barWidth,
            barHeight,
            maxBarHeight,
          );
          break;
      }
    }
  }

  void _drawSegmentedBar(
    Canvas canvas,
    double x,
    double bottom,
    double barWidth,
    int litSegments,
    int segmentCount,
    double segmentHeight,
    double totalSegmentHeight,
  ) {
    final colors = settings.colorScheme.colors;

    for (int seg = 0; seg < segmentCount; seg++) {
      final y =
          bottom -
          (seg + 1) * totalSegmentHeight +
          (totalSegmentHeight - segmentHeight);
      final isLit = seg < litSegments;

      // Color based on segment position (bottom=green, top=red)
      final segmentRatio = seg / (segmentCount - 1);
      Color color;
      if (segmentRatio < 0.5) {
        color = Color.lerp(colors[0], colors[1], segmentRatio * 2)!;
      } else {
        color = Color.lerp(colors[1], colors[2], (segmentRatio - 0.5) * 2)!;
      }

      final paint = Paint()
        ..color = isLit ? color : color.withAlpha(25)
        ..style = PaintingStyle.fill;

      // Sharp rectangle (no rounded corners) for pixelated look
      final rect = Rect.fromLTWH(x, y, barWidth, segmentHeight);
      canvas.drawRect(rect, paint);

      // Add subtle highlight on lit segments
      if (isLit) {
        final highlightPaint = Paint()
          ..color = Colors.white.withAlpha(40)
          ..style = PaintingStyle.fill;
        final highlightRect = Rect.fromLTWH(
          x,
          y,
          barWidth,
          segmentHeight * 0.3,
        );
        canvas.drawRect(highlightRect, highlightPaint);
      }
    }
  }

  void _drawSolidBar(
    Canvas canvas,
    double x,
    double bottom,
    double barWidth,
    double barHeight,
    double maxBarHeight,
  ) {
    final colors = settings.colorScheme.colors;
    final normalizedHeight = (barHeight / maxBarHeight).clamp(0.0, 1.0);

    Color color;
    if (normalizedHeight < 0.5) {
      color = Color.lerp(colors[0], colors[1], normalizedHeight * 2)!;
    } else {
      color = Color.lerp(colors[1], colors[2], (normalizedHeight - 0.5) * 2)!;
    }

    final y = bottom - max(4.0, barHeight);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(x, y, barWidth, max(4.0, barHeight)), paint);
  }

  void _drawGlowBar(
    Canvas canvas,
    double x,
    double bottom,
    double barWidth,
    double barHeight,
    double maxBarHeight,
  ) {
    final colors = settings.colorScheme.colors;
    final normalizedHeight = (barHeight / maxBarHeight).clamp(0.0, 1.0);

    Color color;
    if (normalizedHeight < 0.5) {
      color = Color.lerp(colors[0], colors[1], normalizedHeight * 2)!;
    } else {
      color = Color.lerp(colors[1], colors[2], (normalizedHeight - 0.5) * 2)!;
    }

    final y = bottom - max(4.0, barHeight);
    final actualHeight = max(4.0, barHeight);

    // Glow effect
    final glowPaint = Paint()
      ..color = color.withAlpha(60)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRect(
      Rect.fromLTWH(x - 4, y - 4, barWidth + 8, actualHeight + 8),
      glowPaint,
    );

    // Main bar
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [color, color.withAlpha(180)],
      ).createShader(Rect.fromLTWH(x, y, barWidth, actualHeight));

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, barWidth, actualHeight),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, paint);

    // Top highlight
    final highlightPaint = Paint()..color = Colors.white.withAlpha(80);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, min(4, actualHeight)),
        const Radius.circular(3),
      ),
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    return true; // Always repaint for smooth animation
  }
}
