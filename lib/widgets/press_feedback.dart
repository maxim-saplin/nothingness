import 'package:flutter/material.dart';

/// B-030 — universal press-feedback wrapper. Wraps a tappable child with a [GestureDetector] that flips an [AnimatedOpacity] on touch-down for immediate visual confirmation. Long-press handlers are forwarded verbatim (no long-press visual state). Fade-out is longer than fade-in so a brief tap still dips visibly.
class PressFeedback extends StatefulWidget {
  const PressFeedback({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.behavior = HitTestBehavior.opaque,
    this.dimKey,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final void Function(LongPressEndDetails)? onLongPressEnd;
  final HitTestBehavior behavior;

  /// Optional key forwarded to the inner [AnimatedOpacity] so hosts (e.g. [MediaButton]) expose a stable dip handle for tests.
  final Key? dimKey;

  /// Opacity applied while a touch is held; 0.4 is the smallest value that still reads as a deliberate dip, not a flicker.
  static const double pressedOpacity = 0.4;

  /// Fade duration applied as the press is registered.
  static const Duration fadeInDuration = Duration(milliseconds: 120);

  /// Fade duration on release. Longer than fade-in so a quick tap still produces a visible dip.
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
        key: widget.dimKey,
        opacity: _pressed ? PressFeedback.pressedOpacity : 1.0,
        duration:
            _pressed ? PressFeedback.fadeInDuration : PressFeedback.fadeOutDuration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
