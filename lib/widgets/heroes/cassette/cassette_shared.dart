import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/screen_config.dart';

// ---------------------------------------------------------------------------
// ReelSpin
// ---------------------------------------------------------------------------

/// Animates a cassette reel while playing, easing to a stop when paused.
///
/// PERF CONTRACT (spectrum rebuild storm lesson, 3.9.1+63):
/// This widget drives a LOCAL AnimationController — it NEVER calls
/// PlaybackController.notifyListeners and never triggers a tree-wide rebuild.
/// The [builder] receives the radian angle and MUST be wrapped in a
/// RepaintBoundary by the caller so reel rotation stays in its own layer and
/// does not invalidate surrounding widgets on every 60fps tick.
class ReelSpin extends StatefulWidget {
  const ReelSpin({
    super.key,
    required this.isPlaying,
    required this.builder,
    this.rpm = 1.8,
  });

  final bool isPlaying;

  /// Called with the current angle in radians (0 .. 2π).
  final Widget Function(BuildContext context, double angleRad) builder;

  /// Rotation speed in revolutions per minute when playing.
  final double rpm;

  @override
  State<ReelSpin> createState() => _ReelSpinState();
}

class _ReelSpinState extends State<ReelSpin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _angleRad = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      // One full revolution duration from rpm.
      duration: Duration(
        milliseconds: (60000 / widget.rpm).round(),
      ),
    )..addListener(_onTick);
    if (widget.isPlaying) _ctrl.repeat();
  }

  void _onTick() {
    setState(() => _angleRad = _ctrl.value * 2 * 3.141592653589793);
  }

  @override
  void didUpdateWidget(ReelSpin old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying != old.isPlaying) {
      if (widget.isPlaying) {
        // Resume from current angle without a jump.
        _ctrl
          ..value = _angleRad / (2 * 3.141592653589793)
          ..repeat();
      } else {
        _ctrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _ctrl
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _angleRad);
}

// ---------------------------------------------------------------------------
// tapeProgress
// ---------------------------------------------------------------------------

/// Maps position/duration to a 0..1 tape-progress fraction.
/// Returns 0 when duration is zero to avoid divide-by-zero.
double tapeProgress(int positionMs, int durationMs) {
  if (durationMs <= 0) return 0;
  return (positionMs / durationMs).clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// CassetteHaptics
// ---------------------------------------------------------------------------

/// Thin haptic-feedback wrapper that is a NO-OP unless [enabled] is true
/// AND the current platform is mobile (Android / iOS).
class CassetteHaptics {
  const CassetteHaptics({required this.enabled});

  final bool enabled;

  bool get _active =>
      enabled &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> tap() async {
    if (_active) await HapticFeedback.selectionClick();
  }

  Future<void> select() async {
    if (_active) await HapticFeedback.lightImpact();
  }

  Future<void> heavy() async {
    if (_active) await HapticFeedback.heavyImpact();
  }
}

// ---------------------------------------------------------------------------
// CassetteVariantContext
// ---------------------------------------------------------------------------

/// Everything a variant widget needs, with NO global imports.
/// Assemble in [CassetteHero] from the live [PlaybackController].
class CassetteVariantContext {
  const CassetteVariantContext({
    required this.config,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    required this.haptics,
    this.title,
    this.artist,
    this.spectrumListenable,
  });

  final CassetteScreenConfig config;

  /// Track metadata — null when nothing is loaded.
  final String? title;
  final String? artist;

  final bool isPlaying;
  final int positionMs;
  final int durationMs;

  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final void Function(Duration) onSeek;

  /// Optional live spectrum/level source for VU-meter variants.
  /// Variants that need it declare `usesVisualizer: true` in [cassetteVariantMeta].
  final Listenable? spectrumListenable;

  final CassetteHaptics haptics;
}

// ---------------------------------------------------------------------------
// SprocketHub
// ---------------------------------------------------------------------------

/// A cassette reel hub (6-tooth sprocket) drawn procedurally and centred on the
/// box centre by construction — so [Transform.rotate] spins it with zero
/// eccentricity (no asset-extraction wobble). Tinted via [color]; fills its box.
class SprocketHub extends StatelessWidget {
  const SprocketHub({
    required this.color,
    required this.angle,
    this.teeth = 6,
    super.key,
  });

  final Color color;
  final double angle;
  final int teeth;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: _SprocketPainter(color, angle, teeth),
      );
}

class _SprocketPainter extends CustomPainter {
  _SprocketPainter(this.color, this.angle, this.teeth);

  final Color color;
  final double angle;
  final int teeth;

  @override
  void paint(Canvas canvas, Size size) {
    final R = size.shortestSide / 2;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);

    // Thin outer ring + six bold inward teeth around an open centre.
    const rInF = 0.74, rTipF = 0.32, halfWF = 0.155;
    final rIn = R * rInF, rTip = R * rTipF, halfW = R * halfWF;
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: R))
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: rIn)),
      paint,
    );
    // Six teeth pointing inward from the ring toward the open centre.
    for (int i = 0; i < teeth; i++) {
      canvas.save();
      canvas.rotate(i * 2 * math.pi / teeth);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(-halfW, -rIn, halfW, -rTip),
          Radius.circular(halfW * 0.35),
        ),
        paint,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SprocketPainter o) =>
      o.color != color || o.angle != angle || o.teeth != teeth;
}
