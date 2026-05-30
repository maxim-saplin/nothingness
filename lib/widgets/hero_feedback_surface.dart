import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_typography.dart';

/// B-012 — touch-feedback overlay for the Void hero band.
///
/// Wraps the hero with a gesture surface that lights up briefly on taps and
/// directional swipes. Keeps the visualisation underneath untouched (no
/// Material ripple, no colour shift on the hero itself); feedback is drawn
/// in the foreground as a:
///   * **Tap ring** — an expanding monochrome circle outline that fades
///     out at the tap point over ~180 ms.
///   * **Swipe flash** — a `‹` / `›` glyph at the matching edge of the band
///     that fades in then out over ~180 ms when a horizontal swipe has
///     been recognised.
///
/// B-039 adds a **card swipe** transition on top of the flash: when a
/// horizontal swipe trips prev/next, the current hero "card" slides off in
/// the drag direction and the incoming card animates in from the opposite
/// side, instead of the old instant content swap. The slide wraps the hero
/// child (a [FractionalTranslation] + [Opacity]); at rest it is the
/// identity transform so layout and hit-testing are unaffected.
///
/// The overlay paints in `fgSecondary` so it stays visible against any
/// hero visualisation without dominating it. Both effects are pointer-
/// transparent, so the underlying gesture detector still owns hit-testing.
class HeroFeedbackSurface extends StatefulWidget {
  const HeroFeedbackSurface({
    super.key,
    required this.child,
    required this.onTap,
    required this.onHorizontalDragUpdate,
    required this.onHorizontalDragEnd,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  final Widget child;
  final VoidCallback onTap;
  final void Function(DragUpdateDetails) onHorizontalDragUpdate;
  final void Function(DragEndDetails) onHorizontalDragEnd;
  final void Function(DragUpdateDetails)? onVerticalDragUpdate;
  final void Function(DragEndDetails)? onVerticalDragEnd;

  /// Stable keys for widget tests.
  static const Key tapRingKey = ValueKey<String>('hero-tap-ring');
  static const Key swipeFlashKey = ValueKey<String>('hero-swipe-flash');

  /// B-039: key on the [FractionalTranslation] that drives the card slide,
  /// so tests can read its current `translation`.
  static const Key cardSlideKey = ValueKey<String>('hero-card-slide');

  /// Duration of each feedback animation.
  static const Duration ringDuration = Duration(milliseconds: 180);
  static const Duration swipeFlashDuration = Duration(milliseconds: 180);

  /// B-039: duration of the card slide-off / slide-in transition. A touch
  /// longer than the flash so the motion reads as a card moving, not a blink.
  static const Duration cardSwipeDuration = Duration(milliseconds: 300);

  /// Diameter of the tap ring at the end of its expansion.
  static const double ringMaxDiameter = 96.0;

  /// B-030: stroke width of the tap ring outline. Doubled from the
  /// original 1.5 dp because the hairline ring was effectively invisible
  /// against a busy hero on real-hardware testing.
  static const double ringStrokeWidth = 3.0;

  /// B-030: multiplier applied to the painter's `fgSecondary` alpha so the
  /// ring reads against a busy hero. Clamped at the call site so a fully-
  /// opaque source colour stays opaque.
  static const double ringOpacityMultiplier = 1.5;

  @override
  State<HeroFeedbackSurface> createState() => HeroFeedbackSurfaceState();
}

/// Public state type so callers can drive [flashSwipe] via a [GlobalKey].
class HeroFeedbackSurfaceState extends State<HeroFeedbackSurface>
    with TickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final AnimationController _swipeCtrl;
  // B-039: drives the card slide-off / slide-in transition.
  late final AnimationController _cardCtrl;
  Offset? _ringCenter;
  bool _swipeRight = true;
  // B-039: horizontal direction the OUTGOING card slides (as a fraction of
  // the hero width). -1 = exits left (next), +1 = exits right (previous).
  double _cardExitDir = -1;

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

  /// Public hook for callers (e.g. parent screens) to trigger the swipe
  /// flash when their own drag-accumulation logic actually fires
  /// previous/next. Direction `>0` means rightward (next), `<0` means
  /// leftward (previous).
  void flashSwipe(double direction) {
    if (direction == 0) return;
    setState(() => _swipeRight = direction > 0);
    _swipeCtrl
      ..reset()
      ..forward();
  }

  /// B-039: run the card slide. [exitDir] is the horizontal direction the
  /// OUTGOING card travels as a fraction of the hero width: -1 slides it off
  /// to the left (incoming card enters from the right), +1 slides it off to
  /// the right (incoming enters from the left).
  void animateCardSwipe(double exitDir) {
    if (exitDir == 0) return;
    setState(() => _cardExitDir = exitDir);
    _cardCtrl
      ..reset()
      ..forward();
  }

  /// B-039: combined directional feedback for a recognised prev/next swipe —
  /// the edge glyph flash (B-012) plus the card slide. [isNext] selects the
  /// card metaphor direction: `next` slides the current card off to the left
  /// (next enters from the right); `previous` slides it off to the right.
  void triggerSwipe({required bool isNext}) {
    flashSwipe(isNext ? 1 : -1);
    animateCardSwipe(isNext ? -1.0 : 1.0);
  }

  /// B-039: wraps [child] in the card-slide transform driven by [_cardCtrl].
  /// First half (0→0.5): the outgoing card translates from rest toward
  /// [_cardExitDir] and fades out. Second half (0.5→1): the incoming card
  /// (the child now reflects the new track) starts off-screen on the
  /// opposite side and translates back to rest while fading in.
  Widget _buildCardSlide({required Widget child}) {
    return AnimatedBuilder(
      animation: _cardCtrl,
      builder: (context, inner) {
        final t = _cardCtrl.value;
        double dx;
        double opacity;
        if (t <= 0) {
          // At rest — identity transform so layout/hit-testing/measurement
          // (and idle frames) are completely unaffected.
          dx = 0;
          opacity = 1;
        } else if (t < 0.5) {
          final p = t / 0.5;
          dx = _cardExitDir * p;
          opacity = 1 - p;
        } else {
          final p = (t - 0.5) / 0.5;
          dx = -_cardExitDir * (1 - p);
          opacity = p;
        }
        return FractionalTranslation(
          key: HeroFeedbackSurface.cardSlideKey,
          translation: Offset(dx, 0),
          child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: inner),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _spawnRing(d.localPosition),
          onTap: widget.onTap,
          onHorizontalDragUpdate: widget.onHorizontalDragUpdate,
          onHorizontalDragEnd: widget.onHorizontalDragEnd,
          onVerticalDragUpdate: widget.onVerticalDragUpdate,
          onVerticalDragEnd: widget.onVerticalDragEnd,
          // B-039: the hero child rides the card-slide transform. The
          // GestureDetector stays opaque + full-bleed, so hit-testing is
          // unaffected while the card translates. At rest the transform is
          // the identity (dx 0, opacity 1).
          child: _buildCardSlide(child: widget.child),
        ),
        // Tap ring overlay — only mounted when there's a live animation
        // (or one just finished). Pointer-transparent so the gesture
        // detector below still owns hit-testing.
        if (_ringCenter != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                key: HeroFeedbackSurface.tapRingKey,
                animation: _ringCtrl,
                builder: (context, _) {
                  final t = _ringCtrl.value;
                  if (t == 0 || t == 1) {
                    // 0 = idle pre-forward (just reset); 1 = settled. Either
                    // way the ring should be invisible.
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
                // Drop out at the boundaries so the Text widget itself
                // disappears from the tree (helps widget-test finders and
                // avoids paying for an Opacity(0) every frame).
                final t = _swipeCtrl.value;
                if (t == 0 || t == 1) return const SizedBox.shrink();
                // Triangle envelope: fade in over the first half, out over
                // the second so the user perceives a flash rather than a
                // lingering element.
                final envelope = t < 0.5 ? (t / 0.5) : (1 - (t - 0.5) / 0.5);
                return Align(
                  alignment:
                      _swipeRight ? Alignment.centerRight : Alignment.centerLeft,
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
