import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import 'press_feedback.dart';

/// Circular media button (play / prev / next) used by hero skins.
///
/// B-012 — touch-down affordance: the glyph dips in opacity on press via the shared [PressFeedback] state machine (no InkWell/ripple). The dip's [AnimatedOpacity] is flagged with [touchDownDimKey] so widget tests can read its opacity.
class MediaButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool isPrimary;
  final VoidCallback onTap;
  final Color? accentColor;
  final Color? inactiveBackgroundColor;
  final Color? inactiveIconColor;

  const MediaButton({
    super.key,
    required this.icon,
    required this.size,
    this.isPrimary = false,
    required this.onTap,
    this.accentColor,
    this.inactiveBackgroundColor,
    this.inactiveIconColor,
  });

  /// Stable key on the inner [AnimatedOpacity] so widget tests can assert the touch-down dip.
  static const Key touchDownDimKey = ValueKey<String>('media-button-touch-dim');

  /// Opacity applied while a touch is held. B-030 recalibrated 0.55 → 0.4 (the original dip was sub-threshold against the accent backdrop).
  static const double pressedOpacity = 0.4;

  /// Fade-in duration on press. B-030 widened 80 → 120 ms so the dip reads as motion, not a flicker.
  static const Duration fadeInDuration = Duration(milliseconds: 120);

  /// Fade-out duration on release. Longer than fade-in so a brief tap still produces a visible dip.
  static const Duration fadeOutDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final primaryColor = accentColor ?? palette.accent;

    return PressFeedback(
      onTap: onTap,
      behavior: HitTestBehavior.deferToChild,
      dimKey: touchDownDimKey,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPrimary
              ? primaryColor
              : (inactiveBackgroundColor ??
                  palette.fgPrimary.withValues(alpha: 0.05)),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: primaryColor.withAlpha(77),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: isPrimary
              ? palette.background
              : (inactiveIconColor ?? palette.fgPrimary.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}
