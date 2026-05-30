import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import 'retro_lcd_display.dart';

/// Touch surface for the hero band. Tap zones: left → previous, centre →
/// play/pause, right → next. Horizontal drag → relative seek (full width maps
/// to the whole track; commits once on release). Overlays: tap ring (B-012 /
/// B-030), directional edge flash, and the seek HUD — all pointer-transparent,
/// so the GestureDetector owns every hit-test and the child passes through untransformed.
class HeroFeedbackSurface extends StatefulWidget {
  const HeroFeedbackSurface({
    super.key,
    required this.child,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    required this.positionMs,
    required this.durationMs,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  final Widget child;

  /// Center-third tap.
  final VoidCallback onPlayPause;

  /// Left-third tap.
  final VoidCallback onPrevious;

  /// Right-third tap.
  final VoidCallback onNext;

  /// Commit a seek to [target]. Called once, when the drag is released.
  final void Function(Duration target) onSeek;

  /// Current playback position in ms — read at drag start (a getter, not a
  /// watched value, so the hero is never rebuilt on every position tick).
  final int Function() positionMs;

  /// Current track duration in ms — read at drag start.
  final int Function() durationMs;

  final void Function(DragUpdateDetails)? onVerticalDragUpdate;
  final void Function(DragEndDetails)? onVerticalDragEnd;

  /// Stable keys for widget tests.
  static const Key tapRingKey = ValueKey<String>('hero-tap-ring');
  static const Key swipeFlashKey = ValueKey<String>('hero-swipe-flash');
  static const Key seekHudKey = ValueKey<String>('hero-seek-hud');

  /// Duration of each feedback animation.
  static const Duration ringDuration = Duration(milliseconds: 180);
  static const Duration swipeFlashDuration = Duration(milliseconds: 180);

  /// Diameter of the tap ring at the end of its expansion.
  static const double ringMaxDiameter = 96.0;

  /// B-030: stroke width of the tap ring outline.
  static const double ringStrokeWidth = 3.0;

  /// B-030: multiplier applied to the painter's `fgSecondary` alpha.
  static const double ringOpacityMultiplier = 1.5;

  @override
  State<HeroFeedbackSurface> createState() => HeroFeedbackSurfaceState();
}

/// Public state type so callers can drive [flashSwipe] via a [GlobalKey].
class HeroFeedbackSurfaceState extends State<HeroFeedbackSurface>
    with TickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final AnimationController _swipeCtrl;
  Offset? _ringCenter;
  bool _swipeRight = true;

  /// Most-recent measured hero width (from the build's [LayoutBuilder]).
  double _width = 1;

  bool _seeking = false;
  int _seekStartMs = 0;
  int _seekDurationMs = 0;
  double _seekAccumDx = 0;
  int _seekTargetMs = 0;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: HeroFeedbackSurface.ringDuration,
    );
    _swipeCtrl = AnimationController(
      vsync: this,
      duration: HeroFeedbackSurface.swipeFlashDuration,
    );
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _swipeCtrl.dispose();
    super.dispose();
  }

  void _spawnRing(Offset localPosition) {
    setState(() => _ringCenter = localPosition);
    _ringCtrl
      ..reset()
      ..forward();
  }

  /// Edge-glyph flash. Direction `>0` = rightward (`›`, next), `<0` = leftward
  /// (`‹`, previous).
  void flashSwipe(double direction) {
    if (direction == 0) return;
    setState(() => _swipeRight = direction > 0);
    _swipeCtrl
      ..reset()
      ..forward();
  }

  void _onTapUp(TapUpDetails d) {
    final dx = d.localPosition.dx;
    if (dx < _width / 3) {
      flashSwipe(-1);
      widget.onPrevious();
    } else if (dx > _width * 2 / 3) {
      flashSwipe(1);
      widget.onNext();
    } else {
      widget.onPlayPause();
    }
  }

  void _onSeekStart(DragStartDetails _) {
    setState(() {
      _seeking = true;
      _seekStartMs = widget.positionMs();
      _seekDurationMs = widget.durationMs();
      _seekAccumDx = 0;
      _seekTargetMs = _seekStartMs;
    });
  }

  void _onSeekUpdate(DragUpdateDetails d) {
    if (_seekDurationMs <= 0) return;
    _seekAccumDx += d.primaryDelta ?? 0;
    final raw = _seekStartMs + (_seekAccumDx / _width) * _seekDurationMs;
    setState(() {
      _seekTargetMs = raw.clamp(0, _seekDurationMs.toDouble()).round();
    });
  }

  void _onSeekEnd(DragEndDetails _) {
    final hadDuration = _seekDurationMs > 0;
    final target = _seekTargetMs;
    setState(() => _seeking = false);
    if (hadDuration) {
      widget.onSeek(Duration(milliseconds: target));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          _width = constraints.maxWidth;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _spawnRing(d.localPosition),
              onTapUp: _onTapUp,
              onHorizontalDragStart: _onSeekStart,
              onHorizontalDragUpdate: _onSeekUpdate,
              onHorizontalDragEnd: _onSeekEnd,
              onVerticalDragUpdate: widget.onVerticalDragUpdate,
              onVerticalDragEnd: widget.onVerticalDragEnd,
              child: widget.child,
            ),
            // Tap ring overlay — pointer-transparent.
            if (_ringCenter != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    key: HeroFeedbackSurface.tapRingKey,
                    animation: _ringCtrl,
                    builder: (context, _) {
                      final t = _ringCtrl.value;
                      if (t == 0 || t == 1) {
                        // 0 = idle pre-forward, 1 = settled — invisible either way.
                        return const SizedBox.shrink();
                      }
                      return CustomPaint(
                        painter: _TapRingPainter(
                          center: _ringCenter!,
                          progress: t,
                          color: palette.fgSecondary,
                        ),
                      );
                    },
                  ),
                ),
              ),
            // Edge flash — directional glyph for a prev/next zone tap.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  key: HeroFeedbackSurface.swipeFlashKey,
                  animation: _swipeCtrl,
                  builder: (context, _) {
                    final t = _swipeCtrl.value;
                    if (t == 0 || t == 1) return const SizedBox.shrink();
                    // Triangle envelope: fade in then out so it reads as a flash.
                    final envelope =
                        t < 0.5 ? (t / 0.5) : (1 - (t - 0.5) / 0.5);
                    return Align(
                      alignment: _swipeRight
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Opacity(
                          opacity: envelope.clamp(0.0, 1.0),
                          child: Text(
                            _swipeRight ? '›' : '‹', // › / ‹
                            style: TextStyle(
                              color: palette.fgSecondary,
                              fontFamily: typography.monoFamily,
                              fontSize: typography.heroSize,
                              height: 1,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Seek HUD — time readout + preview line, only while scrubbing.
            if (_seeking)
              Positioned.fill(
                child: IgnorePointer(
                  child: _SeekHud(
                    fraction: _seekDurationMs <= 0
                        ? 0
                        : (_seekTargetMs / _seekDurationMs).clamp(0.0, 1.0),
                    label: _seekDurationMs <= 0
                        ? '--:-- / --:--'
                        : '${formatClock(_seekTargetMs)} / ${formatClock(_seekDurationMs)}',
                    palette: palette,
                    typography: typography,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Centered time readout + a thin full-width preview line at [fraction].
class _SeekHud extends StatelessWidget {
  const _SeekHud({
    required this.fraction,
    required this.label,
    required this.palette,
    required this.typography,
  });

  final double fraction;
  final String label;
  final AppPalette palette;
  final AppTypography typography;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: HeroFeedbackSurface.seekHudKey,
      fit: StackFit.expand,
      children: [
        Center(
          child: Text(
            label,
            style: TextStyle(
              color: palette.fgPrimary,
              fontFamily: typography.monoFamily,
              fontSize: typography.heroSize * 0.5,
              height: 1,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
        // Preview line: full-height marker at the target x (fraction → -1..1).
        Align(
          alignment: Alignment(fraction * 2 - 1, 0),
          child: FractionallySizedBox(
            heightFactor: 1,
            child: SizedBox(
              width: 2,
              child: ColoredBox(color: palette.progress),
            ),
          ),
        ),
      ],
    );
  }
}

class _TapRingPainter extends CustomPainter {
  _TapRingPainter({
    required this.center,
    required this.progress,
    required this.color,
  });

  final Offset center;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Expand 0 → ringMaxDiameter/2 while fading 1 → 0. B-030: stroke 3 dp +
    // alpha boosted 1.5× so the ring stays visible on any hero.
    final radius = (HeroFeedbackSurface.ringMaxDiameter / 2) * progress;
    final fade = (1 - progress).clamp(0.0, 1.0);
    final baseAlpha = color.a;
    final boosted = (baseAlpha *
            fade *
            HeroFeedbackSurface.ringOpacityMultiplier)
        .clamp(0.0, 1.0);
    final paint = Paint()
      ..color = color.withValues(alpha: boosted)
      ..strokeWidth = HeroFeedbackSurface.ringStrokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _TapRingPainter old) =>
      old.center != center || old.progress != progress || old.color != color;
}
