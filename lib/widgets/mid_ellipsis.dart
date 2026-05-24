import 'package:flutter/material.dart';

/// A single-line text widget that **head-truncates** when the string does
/// not fit the available width — i.e. drops characters from the START and
/// prepends an ellipsis (`…`) so the meaningful **TAIL** survives.
///
/// Despite the name `MidEllipsis` (kept for backlog B-019 continuity), this
/// is really a head-ellipsis. The trade is intentional: for breadcrumb
/// paths and music track titles the informative part is at the end, so
/// the default Flutter `TextOverflow.ellipsis` (tail-clip) is wrong for
/// them.
///
/// Behaviour:
/// - LTR ([TextDirection.ltr]): measure with [TextPainter] from the
///   provided width and chop characters off the front until the result
///   plus the leading `…` fits.
/// - RTL ([TextDirection.rtl]): falls back to a plain [Text] with
///   `overflow: TextOverflow.ellipsis`. In RTL the framework's
///   tail-ellipsis already drops the visual tail (which is the LOGICAL
///   head) — that is what RTL users actually want.
/// - [keepEnd]: optional hard cap on how many characters of the tail to
///   keep, applied **before** the width measurement. Useful when the
///   caller knows a tight budget even on a wide screen.
///
/// The widget never throws under pathological constraints; a zero-width
/// box collapses to just the ellipsis (or empty).
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

  /// Style applied both to the measurement [TextPainter] and the final
  /// [Text]. Must match the on-screen style for correctness.
  final TextStyle style;

  /// Optional hard cap on tail length (in code units). When set, the
  /// widget keeps at most this many trailing characters of [text],
  /// regardless of available width.
  final int? keepEnd;

  /// The ellipsis character; defaults to `…`. Exposed for tests.
  final String ellipsis;

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context);
    if (dir == TextDirection.rtl) {
      // Native tail-ellipsis already does the right thing in RTL.
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth.isInfinite || maxWidth.isNaN) {
          // Unbounded — render the full string; nothing to truncate.
          return Text(text, maxLines: 1, style: style);
        }
        if (maxWidth <= 0) {
          return Text('', maxLines: 1, style: style);
        }

        // Apply the optional hard cap first.
        var candidate = text;
        var capped = false;
        if (keepEnd != null && candidate.length > keepEnd!) {
          candidate = candidate.substring(candidate.length - keepEnd!);
          capped = true;
        }

        final media = MediaQuery.maybeOf(context);
        final textScaler = media?.textScaler ?? TextScaler.noScaling;
        final scaledStyle = style;
        final painter = TextPainter(
          text: TextSpan(text: candidate, style: scaledStyle),
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout(maxWidth: double.infinity);

        // If the (possibly capped) string already fits, render verbatim —
        // unless we already capped, in which case we still need the
        // ellipsis prefix to signal the head was dropped.
        if (!capped && painter.width <= maxWidth) {
          return Text(candidate, maxLines: 1, style: style);
        }
        if (capped && painter.width + _ellipsisWidth(scaledStyle, textScaler) <= maxWidth) {
          return Text(
            '$ellipsis$candidate',
            maxLines: 1,
            style: style,
          );
        }

        // Width-driven head-truncation. Binary-search for the largest
        // suffix whose width plus the ellipsis fits inside maxWidth.
        final ellipsisWidth = _ellipsisWidth(scaledStyle, textScaler);
        if (ellipsisWidth > maxWidth) {
          // Not even the ellipsis fits — collapse.
          return Text('', maxLines: 1, style: style);
        }
        final budget = maxWidth - ellipsisWidth;

        int lo = 0; // smallest suffix length we accept (0 = empty)
        int hi = candidate.length; // largest suffix length
        int best = 0;
        while (lo <= hi) {
          final mid = (lo + hi) >> 1;
          final suffix = candidate.substring(candidate.length - mid);
          painter.text = TextSpan(text: suffix, style: scaledStyle);
          painter.layout(maxWidth: double.infinity);
          if (painter.width <= budget) {
            best = mid;
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
        painter.dispose();

        if (best == 0) {
          return Text(ellipsis, maxLines: 1, style: style);
        }
        final suffix = candidate.substring(candidate.length - best);
        return Text(
          '$ellipsis$suffix',
          maxLines: 1,
          style: style,
        );
      },
    );
  }

  double _ellipsisWidth(TextStyle style, TextScaler textScaler) {
    final p = TextPainter(
      text: TextSpan(text: ellipsis, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: double.infinity);
    final w = p.width;
    p.dispose();
    return w;
  }
}
