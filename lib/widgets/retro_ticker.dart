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
    _timer?.cancel();
    _offset = 0;

    // We can't easily measure text width here without LayoutBuilder + TextPainter,
    // but we can just set up the string for potential scrolling and let the build method determine
    // if we need to animate based on the constraints.
    // However, a simpler "ticker" often just rotates regardless if we want that "retro" feel,
    // or we can try to be smart.
    // Given the request is "slides char by char to show full song name", let's implement the logic
    // to measure in the build method or use a LayoutBuilder.

    // A simple char-by-char scroll usually implies: "TEXT    TEXT    " shifting left.
    // Let's rely on LayoutBuilder in build.
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
          // Fits properly
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
          // Doesn't fit, enable scrolling
          // We construct a padded string: "TEXT    "
          // And we rotate it.
          // Ideally, for a smooth infinite scroll, we want "TEXT    TEXT    "
          
          final gap = ' ' * widget.gapSpaces;
          final scrollingText = '${widget.text}$gap';
          
          // If we haven't started scrolling or text changed
          if (_timer == null || !_timer!.isActive) {
             // We need to defer this to avoid setState during build
             WidgetsBinding.instance.addPostFrameCallback((_) {
               _startScrolling(scrollingText);
             });
          }

          // Calculate the substring to show
          // This is a simple character rotation implementation
          // "HELLO   " -> "ELLO   H" -> "LLO   HE" etc.
          
          // Actually, for a marquee, we usually just render the text offset.
          // But "slides char by char" usually means the string content changes.
          
          if (_displayString.isEmpty) {
             return Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              overflow: TextOverflow.clip,
            );
          }
          
          // Create the rotated string for the current offset
          // If _displayString is "ABC   " (length 6)
          // offset 0: "ABC   "
          // offset 1: "BC   A"
          final effectiveOffset = _offset % _displayString.length;
          final rotated = _displayString.substring(effectiveOffset) + _displayString.substring(0, effectiveOffset);
          
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

