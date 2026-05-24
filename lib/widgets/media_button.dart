import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Circular media button (play / prev / next) used by hero skins and any
/// future bespoke transports.
///
/// B-012 — touch-down affordance: the glyph dips in opacity on press and
/// restores on release / cancel. Stays monochrome / typography-driven; no
/// `InkWell`, no Material ripple. The dip is driven by an [AnimatedOpacity]
/// flagged with [touchDownDimKey] so widget tests can read the current
/// opacity without depending on private state.
class MediaButton extends StatefulWidget {
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

  /// Stable key on the inner [AnimatedOpacity] so widget tests can assert
  /// the touch-down dip without reaching into private state.
  static const Key touchDownDimKey =
      ValueKey<String>('media-button-touch-dim');

  /// Opacity applied while a touch is held. Calibrated to be perceptible on
  /// both light and dark themes without losing legibility.
  static const double pressedOpacity = 0.55;

  /// Fade duration each direction — short enough to feel instantaneous,
  /// long enough to register as motion rather than a flicker.
  static const Duration fadeDuration = Duration(milliseconds: 80);

  @override
  State<MediaButton> createState() => _MediaButtonState();
}

class _MediaButtonState extends State<MediaButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final primaryColor = widget.accentColor ?? palette.accent;
    final secondaryBg = widget.inactiveBackgroundColor ??
        palette.fgPrimary.withValues(alpha: 0.05);
    final secondaryIcon = widget.inactiveIconColor ??
        palette.fgPrimary.withValues(alpha: 0.7);

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedOpacity(
        key: MediaButton.touchDownDimKey,
        opacity: _pressed ? MediaButton.pressedOpacity : 1.0,
        duration: MediaButton.fadeDuration,
        curve: Curves.easeOut,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isPrimary ? primaryColor : secondaryBg,
            boxShadow: widget.isPrimary
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
            widget.icon,
            size: widget.size * 0.5,
            color: widget.isPrimary ? palette.background : secondaryIcon,
          ),
        ),
      ),
    );
  }
}
