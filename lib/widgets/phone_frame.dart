import 'package:flutter/widgets.dart';

/// B-042: renders [child] inside a letterboxed narrow-tall "phone frame" of
/// [frame] logical pixels, centered in the available space, so portrait-phone
/// layout can be exercised on the desktop build. When [frame] is null the
/// child is returned unchanged (full window).
///
/// The [MediaQuery] size override makes `MediaQuery.sizeOf` consumers (responsive
/// layout, typography) see the phone dimensions rather than the desktop window.
/// Debug/desktop tooling only — `main.dart` gates this behind `kDebugMode`.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({
    super.key,
    required this.frame,
    required this.child,
    this.letterboxColor = const Color(0xFF000000),
  });

  final Size? frame;
  final Widget child;
  final Color letterboxColor;

  @override
  Widget build(BuildContext context) {
    final f = frame;
    if (f == null) return child;
    return ColoredBox(
      color: letterboxColor,
      child: Center(
        // FittedBox scales the fixed phone-sized box down to fit the (often
        // shorter, landscape) desktop window while preserving aspect ratio —
        // the same letterbox trick the Polo hero uses. The child still lays
        // out at full phone logical size; only the final pixels are scaled.
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: f.width,
            height: f.height,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: f,
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                viewInsets: EdgeInsets.zero,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
