import 'package:flutter/material.dart';

/// B-030 — universal press-feedback wrapper.
///
/// Wraps any tappable child with a [GestureDetector] that flips an
/// [AnimatedOpacity] on touch-down so the user gets immediate visual
/// confirmation of their tap, independent of how long the downstream
/// action takes to produce its own state change. Long-press handlers are
/// forwarded verbatim; the wrapper does not own long-press visual state.
/// Fade-out is longer than fade-in so a brief tap still produces a
/// visible dip before opacity restores to 1.0.
class PressFeedback extends StatefulWidget {
  const PressFeedback({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final void Function(LongPressEndDetails)? onLongPressEnd;
  final HitTestBehavior behavior;

  /// Opacity applied while a touch is held. Lower = deeper dip; 0.4 was
  /// chosen as the smallest value that still reads as a deliberate dip
  /// rather than a flicker on the phones we tested.
  static const double pressedOpacity = 0.4;

  /// Fade duration applied as the press is registered.
  static const Duration fadeInDuration = Duration(milliseconds: 120);

  /// Fade duration applied on release. Longer than the fade-in so a
  /// quick tap still produces a visible dip before bouncing back.
  static const Duration fadeOutDuration = Duration(milliseconds: 200);

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onLongPressStart: widget.onLongPressStart,
      onLongPressEnd: widget.onLongPressEnd,
      child: AnimatedOpacity(
        opacity: _pressed ? PressFeedback.pressedOpacity : 1.0,
        duration:
            _pressed ? PressFeedback.fadeInDuration : PressFeedback.fadeOutDuration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
