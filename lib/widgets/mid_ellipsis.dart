import 'package:flutter/material.dart';

/// Single-line text that head-truncates: drops chars from the START and prepends `…` so the meaningful TAIL survives (the name is kept for B-019 continuity). LTR measures with [TextPainter]; RTL falls back to plain tail-ellipsis [Text]. [keepEnd] optionally caps tail length first. Never throws — a zero-width box collapses to just the ellipsis (or empty).
class MidEllipsis extends StatelessWidget {
  const MidEllipsis({
    super.key,
    required this.text,
    required this.style,
    this.keepEnd,
    this.ellipsis = '…',
  });

  /// The full string to render.
  final String text;

  /// Style applied to both measurement and the final [Text]; must match the on-screen style for correctness.
  final TextStyle style;

  /// Optional hard cap on tail length (code units), applied regardless of available width.
  final int? keepEnd;

  /// The ellipsis character; defaults to `…`. Exposed for tests.
  final String ellipsis;

  Widget _text(String data) => Text(data, maxLines: 1, style: style);

  @override
  Widget build(BuildContext context) {
    if (Directionality.of(context) == TextDirection.rtl) {
      // Native tail-ellipsis already does the right thing in RTL.
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth.isInfinite || maxWidth.isNaN) return _text(text); // unbounded
        if (maxWidth <= 0) return _text('');

        // Apply the optional hard cap first.
        var candidate = text;
        var capped = false;
        if (keepEnd != null && candidate.length > keepEnd!) {
          candidate = candidate.substring(candidate.length - keepEnd!);
          capped = true;
        }

        final scaler = MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling;
        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          maxLines: 1,
          textScaler: scaler,
        );
        double measure(String s) {
          painter.text = TextSpan(text: s, style: style);
          painter.layout(maxWidth: double.infinity);
          return painter.width;
        }

        final candidateWidth = measure(candidate);
        final ellipsisWidth = measure(ellipsis);

        // Fits verbatim — but a capped string still needs the ellipsis prefix to signal the head was dropped.
        if (!capped && candidateWidth <= maxWidth) return _text(candidate);
        if (capped && candidateWidth + ellipsisWidth <= maxWidth) {
          return _text('$ellipsis$candidate');
        }
        if (ellipsisWidth > maxWidth) return _text(''); // not even `…` fits

        final budget = maxWidth - ellipsisWidth;
        // Binary-search for the largest suffix whose width fits the budget.
        var lo = 0, hi = candidate.length, best = 0;
        while (lo <= hi) {
          final mid = (lo + hi) >> 1;
          if (measure(candidate.substring(candidate.length - mid)) <= budget) {
            best = mid;
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
        painter.dispose();

        if (best == 0) return _text(ellipsis);
        return _text('$ellipsis${candidate.substring(candidate.length - best)}');
      },
    );
  }
}
