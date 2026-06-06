import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class RetroTicker extends HookWidget {
  final String text;
  final TextStyle style;
  final Duration scrollInterval;
  final int gapSpaces;

  const RetroTicker({
    super.key,
    required this.text,
    required this.style,
    this.scrollInterval = const Duration(milliseconds: 550),
    this.gapSpaces = 4,
  });

  @override
  Widget build(BuildContext context) {
    // Mutable marquee state, held across rebuilds.
    final displayString = useRef<String>('');
    final timer = useRef<Timer?>(null);
    final offset = useState<int>(0);

    void stopScrolling() {
      timer.value?.cancel();
      timer.value = null;
      offset.value = 0;
    }

    void startScrolling(String fullText) {
      if (timer.value != null && timer.value!.isActive) return;

      displayString.value = fullText;

      timer.value = Timer.periodic(scrollInterval, (t) {
        if (!context.mounted) {
          t.cancel();
          return;
        }

        // B-052: Do not rebuild when the app is in the background. Kept simple
        // without hook overhead since it's just a skip frame.
        final state = WidgetsBinding.instance.lifecycleState;
        if (state != null && state != AppLifecycleState.resumed) {
          return;
        }

        var next = offset.value + 1;
        if (next >= fullText.length) {
          next = 0;
        }
        offset.value = next;
      });
    }

    // Reset the marquee whenever text/style changes (was _checkScroll +
    // didUpdateWidget): cancel any running timer and rewind the offset. Width
    // is measured in build, so the timer is (re)started there as needed.
    useEffect(() {
      timer.value?.cancel();
      timer.value = null;
      offset.value = 0;
      return null;
    }, [text, style]);

    // Cancel the timer on dispose.
    useEffect(() {
      return () => timer.value?.cancel();
    }, const []);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        if (textPainter.width <= constraints.maxWidth) {
          // Fits — render statically and stop any running scroll.
          stopScrolling();
          return Text(
            text,
            style: style,
            textAlign: TextAlign.center,
            overflow: TextOverflow.visible,
            maxLines: 1,
          );
        } else {
          // Overflows — rotate a gap-padded copy char-by-char ("TEXT    ").
          final gap = ' ' * gapSpaces;
          final scrollingText = '$text$gap';

          // Defer start to avoid setState during build.
          if (timer.value == null || !timer.value!.isActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              startScrolling(scrollingText);
            });
          }

          if (displayString.value.isEmpty) {
            return Text(
              text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.clip,
            );
          }

          // Rotate by the current offset: "ABC   " -> "BC   A" -> ...
          final effectiveOffset = offset.value % displayString.value.length;
          final rotated = displayString.value.substring(effectiveOffset) +
              displayString.value.substring(0, effectiveOffset);

          return Text(
            rotated,
            style: style,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          );
        }
      },
    );
  }
}
