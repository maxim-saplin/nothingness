import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import 'retro_lcd_display.dart';

/// Drives the directional edge flash from outside the widget (replaces the old
/// `GlobalKey<HeroFeedbackSurfaceState>.flashSwipe`). Each [flash] bumps a
/// sequence counter + records the direction, then notifies; the surface listens
/// and runs one flash animation per bump.
class HeroFlashController extends ChangeNotifier {
  int _seq = 0;
  int dir = 0;

  /// Latest flash bump count — distinct values let listeners de-dupe rebuilds.
  int get seq => _seq;

  /// Fire an edge flash. `d > 0` = rightward (`›`, next), `d < 0` = leftward
  /// (`‹`, previous); `d == 0` is ignored.
  void flash(int d) {
    if (d == 0) return;
    dir = d;
    _seq++;
    notifyListeners();
  }
}

/// Touch surface for the hero band. Tap zones: left → previous, centre →
/// play/pause, right → next. Horizontal drag → relative seek (full width maps
/// to the whole track; commits once on release). Overlays: tap ring (B-012 /
/// B-030), directional edge flash, and the seek HUD — all pointer-transparent,
/// so the GestureDetector owns every hit-test and the child passes through untransformed.
class HeroFeedbackSurface extends HookWidget {
  const HeroFeedbackSurface({
    super.key,
    required this.child,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    required this.positionMs,
    required this.durationMs,
    this.flashController,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  final Widget child;

  /// Optional external driver for the edge flash (prev/next from a drag).
  final HeroFlashController? flashController;

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
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    final ringCtrl =
        useAnimationController(duration: HeroFeedbackSurface.ringDuration);
    final swipeCtrl =
        useAnimationController(duration: HeroFeedbackSurface.swipeFlashDuration);

    final ringCenter = useState<Offset?>(null);
    final swipeRight = useState(true);

    // Most-recent measured hero width (from the build's [LayoutBuilder]); a ref
    // since it's read inside gesture handlers, not a rebuild trigger.
    final width = useRef<double>(1);

    final seeking = useState(false);
    final seekStartMs = useRef<int>(0);
    final seekDurationMs = useRef<int>(0);
    final seekAccumDx = useRef<double>(0);
    final seekTargetMs = useState<int>(0);

    // Edge-glyph flash. Direction `>0` = rightward (`›`, next), `<0` = leftward
    // (`‹`, previous).
    void flashSwipe(double direction) {
      if (direction == 0) return;
      swipeRight.value = direction > 0;
      swipeCtrl
        ..reset()
        ..forward();
    }

    // B-012: external flash driver — run one flash per controller bump using the
    // recorded direction. useListenable rebuilds on each notify so the effect's
    // [seq] dep changes; the first run (no prior seq) is skipped so a fresh mount
    // doesn't flash spuriously.
    final flashController = this.flashController;
    final seq = flashController?.seq ?? 0;
    useListenable(flashController);
    useEffect(() {
      if (flashController != null && seq > 0) {
        flashSwipe(flashController.dir.toDouble());
      }
      return null;
    }, [seq]);

    void spawnRing(Offset localPosition) {
      ringCenter.value = localPosition;
      ringCtrl
        ..reset()
        ..forward();
    }

    void onTapUp(TapUpDetails d) {
      final dx = d.localPosition.dx;
      if (dx < width.value / 3) {
        flashSwipe(-1);
        onPrevious();
      } else if (dx > width.value * 2 / 3) {
        flashSwipe(1);
        onNext();
      } else {
        onPlayPause();
      }
    }

    void onSeekStart(DragStartDetails _) {
      seekStartMs.value = positionMs();
      seekDurationMs.value = durationMs();
      seekAccumDx.value = 0;
      seekTargetMs.value = seekStartMs.value;
      seeking.value = true;
    }

    void onSeekUpdate(DragUpdateDetails d) {
      if (seekDurationMs.value <= 0) return;
      seekAccumDx.value += d.primaryDelta ?? 0;
      final raw = seekStartMs.value +
          (seekAccumDx.value / width.value) * seekDurationMs.value;
      seekTargetMs.value =
          raw.clamp(0, seekDurationMs.value.toDouble()).round();
    }

    void onSeekEnd(DragEndDetails _) {
      final hadDuration = seekDurationMs.value > 0;
      final target = seekTargetMs.value;
      seeking.value = false;
      if (hadDuration) {
        onSeek(Duration(milliseconds: target));
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          width.value = constraints.maxWidth;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => spawnRing(d.localPosition),
              onTapUp: onTapUp,
              onHorizontalDragStart: onSeekStart,
              onHorizontalDragUpdate: onSeekUpdate,
              onHorizontalDragEnd: onSeekEnd,
              onVerticalDragUpdate: onVerticalDragUpdate,
              onVerticalDragEnd: onVerticalDragEnd,
              child: child,
            ),
            // Tap ring overlay — pointer-transparent.
            if (ringCenter.value != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    key: HeroFeedbackSurface.tapRingKey,
                    animation: ringCtrl,
                    builder: (context, _) {
                      final t = ringCtrl.value;
                      if (t == 0 || t == 1) {
                        // 0 = idle pre-forward, 1 = settled — invisible either way.
                        return const SizedBox.shrink();
                      }
                      return CustomPaint(
                        painter: _TapRingPainter(
                          center: ringCenter.value!,
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
                  animation: swipeCtrl,
                  builder: (context, _) {
                    final t = swipeCtrl.value;
                    if (t == 0 || t == 1) return const SizedBox.shrink();
                    // Triangle envelope: fade in then out so it reads as a flash.
                    final envelope =
                        t < 0.5 ? (t / 0.5) : (1 - (t - 0.5) / 0.5);
                    return Align(
                      alignment: swipeRight.value
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Opacity(
                          opacity: envelope.clamp(0.0, 1.0),
                          child: Text(
                            swipeRight.value ? '›' : '‹', // › / ‹
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
            if (seeking.value)
              Positioned.fill(
                child: IgnorePointer(
                  child: _SeekHud(
                    fraction: seekDurationMs.value <= 0
                        ? 0
                        : (seekTargetMs.value / seekDurationMs.value)
                            .clamp(0.0, 1.0),
                    label: seekDurationMs.value <= 0
                        ? '--:-- / --:--'
                        : '${formatClock(seekTargetMs.value)} / ${formatClock(seekDurationMs.value)}',
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
