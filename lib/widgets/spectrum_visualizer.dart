import 'dart:math';

import 'package:flutter/material.dart';

import '../models/spectrum_settings.dart';
import '../theme/app_palette.dart';

class SpectrumVisualizer extends StatelessWidget {
  final List<double> data;
  final SpectrumSettings settings;

  /// Optional override that bypasses [SpectrumSettings.colorScheme]. Used by
  /// the Spectrum hero to paint a monochrome variant against the active Void
  /// palette regardless of the user's saved colour-scheme preference.
  final List<Color>? colorsOverride;

  const SpectrumVisualizer({
    super.key,
    required this.data,
    required this.settings,
    this.colorsOverride,
  });

  // 3-stop gradient colour for a 0..1 ratio (bottom→top).
  static Color _gradientColor(List<Color> c, double r) => r < 0.5
      ? Color.lerp(c[0], c[1], r * 2)!
      : Color.lerp(c[1], c[2], (r - 0.5) * 2)!;

  // Frequency labels (logarithmic distribution), keyed by bar count.
  static const Map<int, List<String>> _labelsByCount = {
    8: ['60', '150', '400', '1k', '2.5k', '6k', '10k', '16k'],
    12: ['60', '100', '200', '400', '800', '1.5k', '3k', '5k', '8k', '11k',
        '14k', '16k'],
    24: ['31', '50', '70', '100', '140', '200', '280', '400', '560', '800',
        '1.1k', '1.6k', '2.2k', '3k', '4k', '5.5k', '7k', '9k', '11k', '13k',
        '14k', '15k', '16k', '18k'],
  };

  @override
  Widget build(BuildContext context) {
    final count = settings.barCount.count;
    final resampled = _resample(data, count);
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final colors = colorsOverride ?? settings.colorScheme.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final ideal = count * 24.0 * 1.4; // 24px bars, 0.4 gap ratio.
        final width = min(constraints.maxWidth, ideal);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Center(
                child: SizedBox(
                  width: width,
                  child: CustomPaint(
                    painter: _SpectrumPainter(
                      data: resampled,
                      style: settings.barStyle,
                      isLight: theme.brightness == Brightness.light,
                      fgPrimary: palette.fgPrimary,
                      colors: colors,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: SizedBox(width: width, child: _labelsRow(count, palette)),
            ),
          ],
        );
      },
    );
  }

  Widget _labelsRow(int count, AppPalette palette) {
    final labels = _labelsByCount[count]!;
    final every = count == 24 ? 3 : (count == 12 ? 2 : 1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(count, (i) {
        final show = i % every == 0 || i == count - 1;
        return Expanded(
          child: Text(
            show ? labels[i] : '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color: palette.fgSecondary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }),
    );
  }

  // Resample [source] to [target] bars, taking the max in each range for a
  // more responsive reading.
  List<double> _resample(List<double> source, int target) {
    if (source.isEmpty) return List.filled(target, 0.0);
    if (source.length == target) return source;
    final ratio = source.length / target;
    return List.generate(target, (i) {
      final start = (i * ratio).floor();
      final end = ((i + 1) * ratio).floor().clamp(start + 1, source.length);
      var maxVal = 0.0;
      for (var j = start; j < end; j++) {
        if (source[j] > maxVal) maxVal = source[j];
      }
      return maxVal;
    });
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> data;
  final BarStyle style;
  final bool isLight;
  final Color fgPrimary;
  final List<Color> colors;

  _SpectrumPainter({
    required this.data,
    required this.style,
    required this.isLight,
    required this.fgPrimary,
    required this.colors,
  });

  static const _segmentCount = 16; // 80s pixelated look.

  Paint _fill(Color color) => Paint()..color = color;

  Color _at(double ratio) =>
      SpectrumVisualizer._gradientColor(colors, ratio.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final n = data.length;
    final cell = size.width / n;
    final barWidth = cell * 0.65;
    final gap = cell * 0.35;
    final maxH = size.height;
    final segH = maxH / _segmentCount;
    final litSegH = segH - segH * 0.15; // 0.15 inter-segment gap.

    for (var i = 0; i < n; i++) {
      final barHeight = data[i] * maxH;
      final x = i * (barWidth + gap) + gap / 2;
      switch (style) {
        case BarStyle.segmented:
          final lit = (barHeight / segH).ceil().clamp(0, _segmentCount);
          _segmented(canvas, x, maxH, barWidth, lit, segH, litSegH);
        case BarStyle.solid:
          final h = max(4.0, barHeight);
          canvas.drawRect(
            Rect.fromLTWH(x, maxH - h, barWidth, h),
            _fill(_at(barHeight / maxH)),
          );
        case BarStyle.glow:
          _glow(canvas, x, maxH, barWidth, barHeight, maxH);
      }
    }
  }

  void _segmented(Canvas canvas, double x, double bottom, double barWidth,
      int lit, double segH, double litSegH) {
    for (var seg = 0; seg < _segmentCount; seg++) {
      final y = bottom - (seg + 1) * segH + (segH - litSegH);
      // Colour by segment position (bottom=green, top=red).
      final color =
          SpectrumVisualizer._gradientColor(colors, seg / (_segmentCount - 1));
      final isLit = seg < lit;
      // Unlit: in the light variant alpha 25 is imperceptible on white, so mix
      // toward fgPrimary to keep the grid readable while hinting at the
      // segment's chromatic position.
      final fillColor = isLit
          ? color
          : (isLight
              ? Color.lerp(color, fgPrimary, 0.55)!.withAlpha(70)
              : color.withAlpha(25));
      canvas.drawRect(
        Rect.fromLTWH(x, y, barWidth, litSegH),
        _fill(fillColor),
      );
      // Subtle highlight on lit segments — ink tone reads in both variants.
      if (isLit) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, barWidth, litSegH * 0.3),
          _fill((isLight ? Colors.black : Colors.white).withAlpha(40)),
        );
      }
    }
  }

  void _glow(Canvas canvas, double x, double bottom, double barWidth,
      double barHeight, double maxH) {
    final color = _at(barHeight / maxH);
    final h = max(4.0, barHeight);
    final y = bottom - h;
    final rect = Rect.fromLTWH(x, y, barWidth, h);
    const radius = Radius.circular(3);
    canvas.drawRect(
      rect.inflate(4),
      Paint()
        ..color = color.withAlpha(60)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [color, color.withAlpha(180)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, min(4, h)),
        radius,
      ),
      Paint()..color = Colors.white.withAlpha(80),
    );
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) => true;
}
