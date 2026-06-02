import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_palette.dart';
import 'cassette_shared.dart';

/// VARIANT 7 (minimal) — "Minimal Flat Reels (theme-native)".
///
/// The stripped-back, Dieter-Rams reading of a cassette: two stacked hubs drawn
/// as thin concentric-stroke reels in the theme palette, joined by a taut tape
/// line whose wound/unwound balance reflects progress. The hubs reuse the real
/// cassette sprocket sprite (`cassette_hub.png`) so the centres match the
/// asset-based variants.
class CassetteVariant7 extends StatelessWidget {
  const CassetteVariant7(this.ctx, {super.key});

  final CassetteVariantContext ctx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = theme.extension<AppPalette>()!;
    final progress = tapeProgress(ctx.positionMs, ctx.durationMs);

    final titleStyle =
        (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      color: p.fgPrimary,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      height: 1.15,
    );
    final artistStyle = (theme.textTheme.titleMedium ?? const TextStyle())
        .copyWith(color: p.fgSecondary, letterSpacing: 0.4);

    return ColoredBox(
      color: p.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SIDE A',
              style: (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
                color: p.fgTertiary,
                letterSpacing: 4,
                fontWeight: FontWeight.w600,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth, h = box.maxHeight;
                  final cx = w / 2;
                  final wellR = math.min(w * 0.40, h * 0.26);
                  final gap = wellR * 0.62;
                  final top = Offset(cx, h / 2 - wellR - gap / 2);
                  final bottom = Offset(cx, h / 2 + wellR + gap / 2);
                  final topFill = 1.0 + (0.34 - 1.0) * progress;
                  final bottomFill = 0.34 + (1.0 - 0.34) * progress;
                  final hubD = wellR * 0.64;

                  return RepaintBoundary(
                    child: ReelSpin(
                      isPlaying: ctx.isPlaying,
                      rpm: 8,
                      builder: (context, angle) => Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _FlatReelsPainter(
                                progress: progress,
                                ink: p.fgPrimary,
                                hairline: p.divider,
                                accent: p.accent,
                                muted: p.fgTertiary,
                              ),
                              size: Size.infinite,
                            ),
                          ),
                          _hub(top, hubD, angle / topFill, p.fgPrimary),
                          _hub(bottom, hubD, angle / bottomFill, p.fgPrimary),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(
              ctx.title ?? 'No tape loaded',
              style: titleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.linear(ctx.config.textScale),
            ),
            if (ctx.artist != null) ...[
              const SizedBox(height: 6),
              Text(
                ctx.artist!,
                style: artistStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.linear(ctx.config.textScale),
              ),
            ],
            const SizedBox(height: 18),
            _ProgressLine(
              progress: progress,
              track: p.divider,
              fill: p.progress,
              positionMs: ctx.positionMs,
              durationMs: ctx.durationMs,
              label: p.fgTertiary,
              textScale: ctx.config.textScale,
            ),
          ],
        ),
      ),
    );
  }

  Widget _hub(Offset c, double d, double rot, Color ink) => Positioned(
        left: c.dx - d / 2,
        top: c.dy - d / 2,
        width: d,
        height: d,
        child: SprocketHub(color: ink, angle: rot),
      );
}

/// Two stacked reels joined by a taut tape line; supply (top) feeds the take-up
/// (bottom) reel as progress grows. Thin strokes only; the hubs are drawn as
/// sprite widgets on top (see [CassetteVariant7._hub]).
class _FlatReelsPainter extends CustomPainter {
  _FlatReelsPainter({
    required this.progress,
    required this.ink,
    required this.hairline,
    required this.accent,
    required this.muted,
  });

  final double progress;
  final Color ink;
  final Color hairline;
  final Color accent;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final wellR = math.min(size.width * 0.40, size.height * 0.26);
    final gap = wellR * 0.62;
    final top = Offset(cx, size.height / 2 - wellR - gap / 2);
    final bottom = Offset(cx, size.height / 2 + wellR + gap / 2);
    final topFill = 1.0 + (0.34 - 1.0) * progress;
    final bottomFill = 0.34 + (1.0 - 0.34) * progress;

    _drawTape(canvas, top, bottom, wellR, topFill, bottomFill);
    _drawReel(canvas, top, wellR, topFill);
    _drawReel(canvas, bottom, wellR, bottomFill);
  }

  void _drawReel(Canvas canvas, Offset c, double wellR, double fill) {
    final packR = wellR * fill;
    final hubR = wellR * 0.30;

    canvas.drawCircle(
      c,
      wellR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = hairline,
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = muted.withValues(alpha: 0.55);
    for (double rr = hubR + 4; rr <= packR; rr += 4.0) {
      canvas.drawCircle(c, rr, ring);
    }
    if (packR > hubR + 2) {
      canvas.drawCircle(
        c,
        packR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = ink.withValues(alpha: 0.85),
      );
    }
  }

  void _drawTape(Canvas canvas, Offset top, Offset bottom, double wellR,
      double topFill, double bottomFill) {
    final rT = wellR * topFill;
    final rB = wellR * bottomFill;
    final d = bottom.dy - top.dy;
    final phi = math.asin(((rT - rB) / d).clamp(-1.0, 1.0));
    final pTop = Offset(top.dx + rT * math.cos(phi), top.dy + rT * math.sin(phi));
    final pBot =
        Offset(bottom.dx + rB * math.cos(phi), bottom.dy + rB * math.sin(phi));
    canvas.drawLine(
      pTop,
      pBot,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = accent.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_FlatReelsPainter old) =>
      old.progress != progress ||
      old.ink != ink ||
      old.hairline != hairline ||
      old.accent != accent ||
      old.muted != muted;
}

/// A single hairline progress bar with monospaced position / duration.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.progress,
    required this.track,
    required this.fill,
    required this.positionMs,
    required this.durationMs,
    required this.label,
    required this.textScale,
  });

  final double progress;
  final Color track;
  final Color fill;
  final int positionMs;
  final int durationMs;
  final Color label;
  final double textScale;

  String _fmt(int ms) {
    final s = (ms / 1000).floor();
    final m = s ~/ 60;
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: label,
      fontSize: 11 * textScale,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 2,
          child: Stack(
            children: [
              ColoredBox(color: track),
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: ColoredBox(color: fill),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(positionMs), style: style),
            Text(_fmt(durationMs), style: style),
          ],
        ),
      ],
    );
  }
}
