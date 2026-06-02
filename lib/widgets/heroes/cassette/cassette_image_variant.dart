import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_palette.dart';
import 'cassette_shared.dart';

/// Colour treatment for the cassette.
enum CassetteScheme { mono, amber, colorful }

/// ============================================================================
/// CASSETTE — composable boilerplate (hand-edit this file).
///
/// Everything is drawn in [_CassettePainter.paint], back-to-front, as three
/// clearly separated layers:
///   1) FRAME  -> _paintFrame()   ← the cassette body/frame. Minimal on purpose;
///                                  build it out here.
///   2) REELS  -> _paintReel() x2 ← the "rolls": wound tape that grows/shrinks
///                                  with playback + a spinning sprocket. KEPT
///                                  from the last variant. Symmetric by
///                                  construction (centres at x = 0.5 ± _kReelDx).
///   3) TITLE  -> _paintTitle()   ← optional track text. Edit/remove freely.
///
/// All geometry knobs are the `_k*` constants below (fractions of cassette
/// width unless noted). Colours per scheme are in [_scheme]. The widget is
/// rotated to vertical by default ([vertical]); set false for landscape.
///
/// Live-edit loop:
///   export DRIVE_TARGET=linux
///   # edit, then:
///   uv run .claude/skills/agent-emulator-debugging/scripts/drive.py reload
///   uv run .claude/skills/agent-emulator-debugging/scripts/drive.py shoot v
/// (cassette is variant 1/2/3 = mono/amber/colour: `drive.py cassettevariant N`)
/// ============================================================================

// ---- GEOMETRY KNOBS (fractions of cassette width) --------------------------
const double _kAspect = 1.60; // cassette w : h
const double _kReelDx = 0.185; // reel centre offset from middle (± from 0.5)
const double _kReelY = 0.56; // reel centre vertical position (fraction of h)
const double _kWellR = 0.150; // reel-well / window radius
const double _kHubR = 0.052; // sprocket radius
const double _kTapeMax = 0.144; // full wound-pack radius (≤ _kWellR)

class CassetteImageVariant extends StatelessWidget {
  const CassetteImageVariant(
    this.ctx, {
    required this.scheme,
    this.vertical = true,
    super.key,
  });

  final CassetteVariantContext ctx;
  final CassetteScheme scheme;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final s = _scheme(Theme.of(context).extension<AppPalette>()!);

    final cassette = LayoutBuilder(
      builder: (context, box) {
        var w = box.maxWidth;
        if (w / _kAspect > box.maxHeight) w = box.maxHeight * _kAspect;
        return Center(
          child: RepaintBoundary(
            child: ReelSpin(
              isPlaying: ctx.isPlaying,
              rpm: 7,
              builder: (context, angle) => CustomPaint(
                size: Size(w, w / _kAspect),
                painter: _CassettePainter(
                  s: s,
                  angle: angle,
                  progress: tapeProgress(ctx.positionMs, ctx.durationMs),
                  title: (ctx.title ?? '').trim(),
                  artist: (ctx.artist ?? '').trim(),
                  textScale: ctx.config.textScale,
                ),
              ),
            ),
          ),
        );
      },
    );

    return ColoredBox(
      color: s.bg,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 54),
                child: vertical
                    ? RotatedBox(quarterTurns: 3, child: cassette)
                    : cassette,
              ),
            ),
            // Transport progress strip (screen-space, below the cassette).
            Positioned(left: 28, right: 28, bottom: 10, child: _progress(s)),
          ],
        ),
      ),
    );
  }

  // ---- COLOURS (edit per scheme) -------------------------------------------
  _Scheme _scheme(AppPalette p) {
    switch (scheme) {
      case CassetteScheme.mono:
        final fg = p.fgPrimary;
        return _Scheme(
          bg: p.background,
          frame: Color.lerp(p.background, fg, 0.55)!,
          well: Color.lerp(p.background, fg, 0.28)!,
          tape: Color.lerp(p.background, fg, 0.62)!,
          hub: fg,
          spindle: p.background,
          text: fg,
          ink: false,
          track: p.divider,
          fill: fg,
        );
      case CassetteScheme.amber:
        return const _Scheme(
          bg: Color(0xFF141019),
          frame: Color(0xFFEDE6D3),
          well: Color(0xFF3A2E22),
          tape: Color(0xFFC79248),
          hub: Color(0xFFEDE6D3),
          spindle: Color(0xFF141019),
          text: Color(0xFFEDE6D3),
          ink: true,
          track: Color(0x33EDE6D3),
          fill: Color(0xFFC79248),
        );
      case CassetteScheme.colorful:
        return const _Scheme(
          bg: Color(0xFF15181E),
          frame: Color(0xFFEFE7D6),
          well: Color(0xFF323A44),
          tape: Color(0xFFE05A48),
          hub: Color(0xFFF3C24F),
          spindle: Color(0xFF15181E),
          text: Color(0xFFEFE7D6),
          ink: true,
          track: Color(0x33EFE7D6),
          fill: Color(0xFFF3C24F),
        );
    }
  }

  Widget _progress(_Scheme s) {
    final frac = tapeProgress(ctx.positionMs, ctx.durationMs);
    String mmss(int ms) {
      final t = (ms / 1000).floor();
      return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 2,
        child: Stack(children: [
          Container(color: s.track),
          FractionallySizedBox(
              widthFactor: frac.clamp(0.0, 1.0),
              child: Container(color: s.fill)),
        ]),
      ),
      const SizedBox(height: 7),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(mmss(ctx.positionMs),
            style: TextStyle(color: s.fill, fontSize: 11)),
        Text(ctx.durationMs > 0 ? mmss(ctx.durationMs) : '--:--',
            style: TextStyle(color: s.fill, fontSize: 11)),
      ]),
    ]);
  }
}

class _Scheme {
  const _Scheme({
    required this.bg,
    required this.frame,
    required this.well,
    required this.tape,
    required this.hub,
    required this.spindle,
    required this.text,
    required this.ink,
    required this.track,
    required this.fill,
  });
  final Color bg, frame, well, tape, hub, spindle, text, track, fill;
  final bool ink; // true → use the handwriting (Caveat) font for the title
}

class _CassettePainter extends CustomPainter {
  _CassettePainter({
    required this.s,
    required this.angle,
    required this.progress,
    required this.title,
    required this.artist,
    required this.textScale,
  });

  final _Scheme s;
  final double angle;
  final double progress;
  final String title;
  final String artist;
  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    final cL = Offset(size.width * (0.5 - _kReelDx), size.height * _kReelY);
    final cR = Offset(size.width * (0.5 + _kReelDx), size.height * _kReelY);

    _paintFrame(canvas, size); // LAYER 1 ← build out the frame here
    _paintReel(canvas, size, cL, 1.0 - progress, angle); // LAYER 2: supply
    _paintReel(canvas, size, cR, progress, angle); //        LAYER 2: take-up
    _paintTitle(canvas, size); // LAYER 3 ← optional title
  }

  // ---- LAYER 1: FRAME (minimal — extend this) ------------------------------
  void _paintFrame(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.045));
    canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.006
          ..color = s.frame);
  }

  // ---- LAYER 2: REEL = wound tape (resizes with [fill]) + sprocket ---------
  // [fill] 0..1 = how wound this reel is. Symmetric by construction.
  void _paintReel(
      Canvas canvas, Size size, Offset c, double fill, double baseAngle) {
    final w = size.width;
    final wellR = w * _kWellR;
    final hubR = w * _kHubR;
    final tapeMax = w * _kTapeMax;
    final packR = hubR + (tapeMax - hubR) * fill.clamp(0.0, 1.0);
    final spin = baseAngle * (tapeMax / packR); // emptier pack → faster spin

    // Well / window boundary.
    canvas.drawCircle(
        c,
        wellR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.004
          ..color = s.well);

    // Wound tape: filled disc + concentric winding lines.
    if (packR > hubR + 0.6) {
      canvas.drawCircle(c, packR, Paint()..color = s.tape);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(s.tape, const Color(0xFF000000), 0.30)!;
      for (double rr = hubR + 3.5; rr < packR - 0.6; rr += 3.5) {
        canvas.drawCircle(c, rr, line);
      }
    }

    _sprocket(canvas, c, hubR, spin);
  }

  // 6-tooth sprocket, centred by construction (rotates with [angle]).
  void _sprocket(Canvas canvas, Offset c, double R, double angle) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final paint = Paint()..color = s.hub;
    final rIn = R * 0.74, rTip = R * 0.34, halfW = R * 0.16;
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: R))
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: rIn)),
      paint,
    );
    for (int i = 0; i < 6; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(-halfW, -rIn, halfW, -rTip),
            Radius.circular(halfW * 0.35)),
        paint,
      );
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, rTip * 0.62, Paint()..color = s.spindle);
    canvas.restore();
  }

  // ---- LAYER 3: TITLE (optional) -------------------------------------------
  void _paintTitle(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = title.isEmpty ? '—' : title;
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
      text: TextSpan(
        text: t,
        style: TextStyle(
          color: s.text,
          fontFamily: s.ink ? 'Caveat' : null,
          fontSize: h * (s.ink ? 0.11 : 0.075) * textScale,
          height: 1.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    )..layout(maxWidth: w * 0.84);
    tp.paint(canvas, Offset(w * 0.08, h * 0.10));
  }

  @override
  bool shouldRepaint(_CassettePainter o) =>
      o.angle != angle ||
      o.progress != progress ||
      o.title != title ||
      o.artist != artist ||
      o.s != s ||
      o.textScale != textScale;
}
