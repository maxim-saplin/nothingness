import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/playback_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import 'retro_lcd_display.dart';
import 'press_feedback.dart';

/// Transport widget pinned above the crumb in the Void chrome (non-immersive only).
class TransportRow extends StatelessWidget {
  const TransportRow({super.key});

  static const Key prevKey = ValueKey<String>('transport-prev');
  static const Key playKey = ValueKey<String>('transport-play');
  static const Key nextKey = ValueKey<String>('transport-next');
  static const Key timeKey = ValueKey<String>('transport-time');
  static const Key seekKey = ValueKey<String>('transport-seek');

  /// Total height of the row. Kept in sync with `_transportHeight` in `void_screen.dart`.
  static const double transportHeight = 56.0;
  static const double _iconRowHeight = 42.0;
  static const double _controlGroupWidth = 144.0;
  static const double _timeRightPadding = 14.0;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final playbackPosition = context
        .select<PlaybackController, ({int positionMs, int durationMs})>(
          (playback) => (
            positionMs: playback.songInfo?.position ?? 0,
            durationMs: playback.songInfo?.duration ?? 0,
          ),
        );
    final timeStyle = TextStyle(
      color: palette.fgSecondary,
      fontFamily: typography.monoFamily,
      fontSize: typography.rowSize,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final timeText = playbackPosition.durationMs > 0
        ? '${formatClock(playbackPosition.positionMs)}/${formatClock(playbackPosition.durationMs)}'
        : '--:--/--:--';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.divider, width: 1)),
      ),
      child: SizedBox(
        height: transportHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(
              child: SizedBox(width: _controlGroupWidth, child: _IconRow()),
            ),
            Positioned(
              top: 0,
              right: _timeRightPadding,
              bottom: 0,
              child: Center(
                child: Text(
                  key: TransportRow.timeKey,
                  timeText,
                  style: timeStyle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-aligned progress hairline and its tap/drag seek surface.
class TransportSeekBar extends StatefulWidget {
  const TransportSeekBar({super.key});

  @override
  State<TransportSeekBar> createState() => _TransportSeekBarState();
}

class _TransportSeekBarState extends State<TransportSeekBar> {
  static const double _hitHeight = 24.0;
  int? _activePointer;
  double? _dragFraction;
  double? _pointerDownFraction;
  bool _dragMoved = false;

  void _startGesture(int pointer, double fraction) {
    _activePointer = pointer;
    _pointerDownFraction = fraction;
    _dragFraction = fraction;
    _dragMoved = false;
  }

  void _updateGesture(int pointer, double fraction) {
    if (_activePointer != pointer) return;
    _dragMoved = true;
    if (_dragFraction == fraction) return;
    setState(() {
      _dragFraction = fraction;
    });
  }

  void _endGesture(int pointer, void Function(double fraction) commit) {
    if (_activePointer != pointer) return;
    final targetFraction = _dragMoved
        ? (_dragFraction ?? _pointerDownFraction)
        : _pointerDownFraction;
    _activePointer = null;
    _pointerDownFraction = null;
    _dragMoved = false;
    if (mounted) {
      setState(() {
        _dragFraction = null;
      });
    }
    if (targetFraction != null) commit(targetFraction);
  }

  void _cancelGesture(int pointer) {
    if (_activePointer != pointer) return;
    _activePointer = null;
    _pointerDownFraction = null;
    _dragMoved = false;
    if (_dragFraction != null && mounted) {
      setState(() {
        _dragFraction = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final player = context.read<PlaybackController>();
    final playbackPosition = context
        .select<PlaybackController, ({int positionMs, int durationMs})>(
          (playback) => (
            positionMs: playback.songInfo?.position ?? 0,
            durationMs: playback.songInfo?.duration ?? 0,
          ),
        );
    final positionMs = playbackPosition.positionMs;
    final durationMs = playbackPosition.durationMs;
    final hasDuration = durationMs > 0;
    final fraction = hasDuration
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      height: _hitHeight,
      child: LayoutBuilder(
        builder: (context, c) {
          final width = c.maxWidth;
          double? fractionFor(double localX) {
            if (!hasDuration || width <= 0) return null;
            return (localX / width).clamp(0.0, 1.0);
          }

          void commitSeek(double seekFraction) {
            player.seek(
              Duration(milliseconds: (seekFraction * durationMs).round()),
            );
          }

          return Listener(
            key: TransportRow.seekKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              final seekFraction = fractionFor(e.localPosition.dx);
              if (seekFraction == null) return;
              _startGesture(e.pointer, seekFraction);
            },
            onPointerMove: (e) {
              final seekFraction = fractionFor(e.localPosition.dx);
              if (seekFraction == null) return;
              _updateGesture(e.pointer, seekFraction);
            },
            onPointerUp: (e) => _endGesture(e.pointer, commitSeek),
            onPointerCancel: (e) => _cancelGesture(e.pointer),
            child: CustomPaint(
              painter: _ProgressPainter(
                fraction: _dragFraction ?? fraction,
                trackColor: palette.divider,
                fillColor: palette.fgPrimary.withValues(alpha: 0.85),
              ),
              size: Size(width, _hitHeight),
            ),
          );
        },
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.fraction,
    required this.trackColor,
    required this.fillColor,
  });

  final double fraction;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Bottom-aligned 1 dp track hairline plus a thicker 1.5 dp filled portion mirroring the progress hairline.
    final y = size.height - 1.0;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = trackColor
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
    if (fraction > 0) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width * fraction, y),
        Paint()
          ..color = fillColor
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.square
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter old) =>
      old.fraction != fraction ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor;
}

class _IconRow extends StatelessWidget {
  const _IconRow();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final player = context.read<PlaybackController>();
    final glyphColor = palette.fgPrimary.withValues(alpha: 0.7);
    final isPlaying = context.select<PlaybackController, bool>(
      (playback) => playback.isPlaying,
    );

    Widget button(Key key, IconData icon, VoidCallback onTap, String label) {
      return Expanded(
        child: Semantics(
          label: label,
          button: true,
          child: PressFeedback(
            key: key,
            onTap: onTap,
            child: SizedBox(
              height: TransportRow._iconRowHeight,
              child: Icon(icon, color: glyphColor, size: 22),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        button(
          TransportRow.prevKey,
          Icons.skip_previous_rounded,
          player.previous,
          'previous',
        ),
        button(
          TransportRow.playKey,
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          player.playPause,
          isPlaying ? 'pause' : 'play',
        ),
        button(
          TransportRow.nextKey,
          Icons.skip_next_rounded,
          player.next,
          'next',
        ),
      ],
    );
  }
}
