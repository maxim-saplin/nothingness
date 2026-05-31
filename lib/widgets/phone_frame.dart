import 'package:flutter/widgets.dart';

/// B-042: renders [child] inside a centered, letterboxed narrow-tall "phone frame" of [frame] logical pixels so portrait-phone layout can be exercised on the desktop build; null [frame] returns the child unchanged. The [MediaQuery] size override makes `MediaQuery.sizeOf` consumers see phone dimensions. Debug/desktop tooling only — gated behind `kDebugMode` in `main.dart`.
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
        // FittedBox scales the fixed phone-sized box to fit the desktop window, preserving aspect ratio; the child still lays out at full phone size, only final pixels are scaled.
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
