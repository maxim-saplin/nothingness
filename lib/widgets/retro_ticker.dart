import 'dart:async';
import 'package:flutter/widgets.dart';

class RetroTicker extends StatefulWidget {
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
  State<RetroTicker> createState() => _RetroTickerState();
}

class _RetroTickerState extends State<RetroTicker> {
  String _displayString = '';
  Timer? _timer;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _checkScroll();
  }

  @override
  void didUpdateWidget(RetroTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _checkScroll();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _checkScroll() {
    // Width is measured in build(); just reset state here.
    _timer?.cancel();
    _offset = 0;
  }

  void _startScrolling(String fullText) {
    if (_timer != null && _timer!.isActive) return;

    _displayString = fullText;

    _timer = Timer.periodic(widget.scrollInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _offset++;
        if (_offset >= fullText.length) {
          _offset = 0;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        if (textPainter.width <= constraints.maxWidth) {
          // Fits — render statically and stop any running scroll.
          _timer?.cancel();
          _offset = 0;
          return Text(
            widget.text,
            style: widget.style,
            textAlign: TextAlign.center,
            overflow: TextOverflow.visible,
            maxLines: 1,
          );
        } else {
          // Overflows — rotate a gap-padded copy char-by-char ("TEXT    ").
          final gap = ' ' * widget.gapSpaces;
          final scrollingText = '${widget.text}$gap';

          // Defer start to avoid setState during build.
          if (_timer == null || !_timer!.isActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _startScrolling(scrollingText);
            });
          }

          if (_displayString.isEmpty) {
            return Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              overflow: TextOverflow.clip,
            );
          }

          // Rotate by the current offset: "ABC   " -> "BC   A" -> ...
          final effectiveOffset = _offset % _displayString.length;
          final rotated = _displayString.substring(effectiveOffset) +
              _displayString.substring(0, effectiveOffset);

          return Text(
            rotated,
            style: widget.style,
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

