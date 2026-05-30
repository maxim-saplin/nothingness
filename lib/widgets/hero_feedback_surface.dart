import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_typography.dart';

/// Touch-feedback + interactive swipe surface for the hero band.
///
/// Wraps the hero with a gesture surface that:
///   * **Tap ring** — an expanding monochrome circle outline that fades out at
///     the tap point over ~180 ms (B-012).
///   * **Swipe flash** — a `‹` / `›` glyph at the matching edge of the band
///     that fades in then out when a horizontal swipe commits to prev/next.
///   * **Interactive card swipe** — the hero "card" tracks the finger during a
///     horizontal drag and commits to a track change **exactly once on
///     release**, then completes the slide (current card exits in the drag
///     direction, the incoming card enters from the opposite side). A drag that
///     doesn't cross the distance/velocity threshold springs back to rest with
///     no track change.
///
/// The single-commit-on-release model is deliberate: the previous
/// implementation accumulated drag distance and fired `next()`/`previous()`
/// *mid-drag* every time a 60-dp threshold was crossed, which meant one long
/// swipe could skip several tracks (and on Android, fire several async
/// platform-channel skips back-to-back — the "stuck / jumpy / skips songs"
/// bug). Now the card follows the finger live and the player is told to change
/// track once, after the gesture ends.
///
/// The overlay paints in `fgSecondary` so it stays visible against any hero
/// visualisation without dominating it. Both feedback overlays are pointer-
/// transparent, so the underlying gesture detector owns all hit-testing.
class HeroFeedbackSurface extends StatefulWidget {
  const HeroFeedbackSurface({
    super.key,
    required this.child,
    required this.onTap,
    required this.onNext,
    required this.onPrevious,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  final Widget child;
  final VoidCallback onTap;

  /// Fired exactly once when a horizontal swipe commits to the NEXT track.
  final VoidCallback onNext;

  /// Fired exactly once when a horizontal swipe commits to the PREVIOUS track.
  final VoidCallback onPrevious;

  final void Function(DragUpdateDetails)? onVerticalDragUpdate;
  final void Function(DragEndDetails)? onVerticalDragEnd;

  /// Stable keys for widget tests.
  static const Key tapRingKey = ValueKey<String>('hero-tap-ring');
  static const Key swipeFlashKey = ValueKey<String>('hero-swipe-flash');

  /// Key on the [FractionalTranslation] that drives the card slide, so tests
  /// can read its current `translation`.
  static const Key cardSlideKey = ValueKey<String>('hero-card-slide');

  /// Duration of each feedback animation.
  static const Duration ringDuration = Duration(milliseconds: 180);
  static const Duration swipeFlashDuration = Duration(milliseconds: 180);

  /// Duration of a full programmatic card slide (exit + enter), used by
  /// [HeroFeedbackSurfaceState.triggerSwipe].
  static const Duration cardSwipeDuration = Duration(milliseconds: 300);

  /// Settle timings for the interactive gesture commit.
  static const Duration cardExitDuration = Duration(milliseconds: 160);
  static const Duration cardEnterDuration = Duration(milliseconds: 220);
  static const Duration cardCancelDuration = Duration(milliseconds: 220);

  /// A drag commits to a track change when it travels past this many logical
  /// pixels OR ends with a flick faster than [swipeVelocityThreshold].
  static const double swipeDistanceThreshold = 60.0;

  /// Flick speed (px/s) that commits a short drag. Tuned to match a PageView
  /// flick — clearly faster than a casual drag.
  static const double swipeVelocityThreshold = 300.0;

  /// Diameter of the tap ring at the end of its expansion.
  static const double ringMaxDiameter = 96.0;

  /// B-030: stroke width of the tap ring outline.
  static const double ringStrokeWidth = 3.0;

  /// B-030: multiplier applied to the painter's `fgSecondary` alpha.
  static const double ringOpacityMultiplier = 1.5;

  @override
  State<HeroFeedbackSurface> createState() => HeroFeedbackSurfaceState();
}

/// How the card slide is currently being driven.
enum _CardPhase {
  /// At rest — identity transform; layout/hit-testing/measurement unaffected.
  idle,

  /// Following the finger live during an active horizontal drag.
  dragging,

  /// A controller-driven lerp between [_fromFrac]/[_fromOpacity] and
  /// [_toFrac]/[_toOpacity] — used for the commit exit, the commit enter, and
  /// the cancel spring-back.
  settle,

  /// Legacy two-phase programmatic slide driven by [triggerSwipe].
  canned,
}

/// Public state type so callers can drive [flashSwipe] / [triggerSwipe] via a
/// [GlobalKey].
class HeroFeedbackSurfaceState extends State<HeroFeedbackSurface>
    with TickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final AnimationController _swipeCtrl;
  // Drives the card slide for both the gesture commit/cancel ([_CardPhase
  // .settle]) and the programmatic [triggerSwipe] ([_CardPhase.canned]).
  late final AnimationController _cardCtrl;
  Offset? _ringCenter;
  bool _swipeRight = true;

  _CardPhase _phase = _CardPhase.idle;

  /// Live horizontal offset of the card as a fraction of the hero width while
  /// [_CardPhase.dragging]. Negative = dragged left (towards `next`).
  double _dragFrac = 0;

  /// Endpoints for a [_CardPhase.settle] lerp.
  double _fromFrac = 0;
  double _toFrac = 0;
  double _fromOpacity = 1;
  double _toOpacity = 1;

  /// Direction the outgoing card travels during a [_CardPhase.canned] slide.
  double _cardExitDir = -1;

  /// Most-recent measured hero width (from the build's [LayoutBuilder]). Used
  /// to convert pixel drag deltas / velocities into width fractions.
  double _width = 1;

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
    _cardCtrl = AnimationController(
      vsync: this,
      duration: HeroFeedbackSurface.cardSwipeDuration,
    );
    // The canned (programmatic) slide returns to rest on completion.
    _cardCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _phase == _CardPhase.canned &&
          mounted) {
        setState(() => _phase = _CardPhase.idle);
      }
    });
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _swipeCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  void _spawnRing(Offset localPosition) {
    setState(() => _ringCenter = localPosition);
    _ringCtrl
      ..reset()
      ..forward();
  }

  /// Edge-glyph flash for a recognised prev/next swipe. Direction `>0` =
  /// rightward (`›`, next), `<0` = leftward (`‹`, previous).
  void flashSwipe(double direction) {
    if (direction == 0) return;
    setState(() => _swipeRight = direction > 0);
    _swipeCtrl
      ..reset()
      ..forward();
  }

  /// Programmatic two-phase card slide (no track change) plus the edge flash.
  /// [isNext] selects the metaphor direction: `next` slides the current card
  /// off to the LEFT (incoming enters from the right); `previous` off to the
  /// RIGHT. Retained for callers/tests that want a purely visual swipe.
  void triggerSwipe({required bool isNext}) {
    flashSwipe(isNext ? 1 : -1);
    setState(() {
      _cardExitDir = isNext ? -1.0 : 1.0;
      _phase = _CardPhase.canned;
    });
    _cardCtrl
      ..duration = HeroFeedbackSurface.cardSwipeDuration
      ..reset()
      ..forward();
  }

  // --- Interactive horizontal drag ------------------------------------------

  double _dragOpacity(double frac) =>
      (1 - 0.25 * frac.abs()).clamp(0.0, 1.0);

  void _onHorizontalDragStart(DragStartDetails _) {
    _cardCtrl.stop();
    setState(() {
      _phase = _CardPhase.dragging;
      _dragFrac = 0;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    setState(() {
      _phase = _CardPhase.dragging;
      _dragFrac =
          (_dragFrac + (d.primaryDelta ?? 0) / _width).clamp(-1.0, 1.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final distance = _dragFrac.abs() * _width;
    final farEnough = distance > HeroFeedbackSurface.swipeDistanceThreshold;
    final fastEnough =
        velocity.abs() > HeroFeedbackSurface.swipeVelocityThreshold;
    if (!farEnough && !fastEnough) {
      _cancelSwipe();
      return;
    }
    // Direction: a sizeable drag follows the drag sign; a short flick follows
    // the velocity sign. Dragging/flicking LEFT (negative) means `next`.
    final bool isNext = farEnough ? _dragFrac < 0 : velocity < 0;
    _commitSwipe(isNext);
  }

  TickerFuture _settle({
    required double from,
    required double to,
    required double fromOpacity,
    required double toOpacity,
    required Duration duration,
    required Curve curve,
  }) {
    setState(() {
      _phase = _CardPhase.settle;
      _fromFrac = from;
      _toFrac = to;
      _fromOpacity = fromOpacity;
      _toOpacity = toOpacity;
    });
    _cardCtrl
      ..duration = duration
      ..reset();
    return _cardCtrl.animateTo(1.0, curve: curve);
  }

  Future<void> _cancelSwipe() async {
    await _settle(
      from: _dragFrac,
      to: 0,
      fromOpacity: _dragOpacity(_dragFrac),
      toOpacity: 1,
      duration: HeroFeedbackSurface.cardCancelDuration,
      curve: Curves.easeOut,
    );
    if (!mounted) return;
    setState(() => _phase = _CardPhase.idle);
  }

  Future<void> _commitSwipe(bool isNext) async {
    final exitDir = isNext ? -1.0 : 1.0;
    flashSwipe(isNext ? 1 : -1);
    // Phase 1: finish the slide-off in the drag direction (old card still
    // shown — the player isn't told to change track until it's off-screen).
    await _settle(
      from: _dragFrac,
      to: exitDir,
      fromOpacity: _dragOpacity(_dragFrac),
      toOpacity: 0,
      duration: HeroFeedbackSurface.cardExitDuration,
      curve: Curves.easeIn,
    );
    if (!mounted) return;
    // Commit the track change exactly once, while the card is off-screen.
    if (isNext) {
      widget.onNext();
    } else {
      widget.onPrevious();
    }
    // Phase 2: the (now updated) card enters from the opposite edge.
    setState(() {
      _phase = _CardPhase.settle;
      _fromFrac = -exitDir;
      _toFrac = 0;
      _fromOpacity = 0;
      _toOpacity = 1;
    });
    _cardCtrl
      ..duration = HeroFeedbackSurface.cardEnterDuration
      ..reset();
    await _cardCtrl.animateTo(1.0, curve: Curves.easeOut);
    if (!mounted) return;
    setState(() => _phase = _CardPhase.idle);
  }

  /// Current card translation fraction + opacity for [_buildCardSlide].
  ({double dx, double opacity}) _cardTransform() {
    switch (_phase) {
      case _CardPhase.idle:
        return (dx: 0, opacity: 1);
      case _CardPhase.dragging:
        return (dx: _dragFrac, opacity: _dragOpacity(_dragFrac));
      case _CardPhase.settle:
        final t = _cardCtrl.value;
        return (
          dx: _fromFrac + (_toFrac - _fromFrac) * t,
          opacity: _fromOpacity + (_toOpacity - _fromOpacity) * t,
        );
      case _CardPhase.canned:
        final t = _cardCtrl.value;
        if (t <= 0) return (dx: 0, opacity: 1);
        if (t < 0.5) {
          final p = t / 0.5;
          return (dx: _cardExitDir * p, opacity: 1 - p);
        }
        final p = (t - 0.5) / 0.5;
        return (dx: -_cardExitDir * (1 - p), opacity: p);
    }
  }

  Widget _buildCardSlide({required Widget child}) {
    return AnimatedBuilder(
      animation: _cardCtrl,
      builder: (context, inner) {
        final tf = _cardTransform();
        return FractionalTranslation(
          key: HeroFeedbackSurface.cardSlideKey,
          translation: Offset(tf.dx, 0),
          child: Opacity(opacity: tf.opacity.clamp(0.0, 1.0), child: inner),
        );
      },
      child: child,
    );
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
              onTap: widget.onTap,
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onVerticalDragUpdate: widget.onVerticalDragUpdate,
              onVerticalDragEnd: widget.onVerticalDragEnd,
              // The hero child rides the card-slide transform. The
              // GestureDetector stays opaque + full-bleed, so hit-testing is
              // unaffected while the card translates. At rest the transform is
              // the identity (dx 0, opacity 1).
              child: _buildCardSlide(child: widget.child),
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
                        // 0 = idle pre-forward; 1 = settled. Either way the
                        // ring should be invisible.
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
            // Swipe flash — directional glyph at the edge of the hero band.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  key: HeroFeedbackSurface.swipeFlashKey,
                  animation: _swipeCtrl,
                  builder: (context, _) {
                    final t = _swipeCtrl.value;
                    if (t == 0 || t == 1) return const SizedBox.shrink();
                    // Triangle envelope: fade in over the first half, out over
                    // the second so it reads as a flash.
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
          ],
        );
      },
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
    // Expand from 0 → ringMaxDiameter/2 while fading 1 → 0. B-030: stroke
    // doubled (1.5 → 3 dp) and the alpha boosted 1.5× so the ring is
    // visible on a hand-held device against any hero visualisation.
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
