import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_player_provider.dart';
import '../theme/app_palette.dart';

/// Lightweight transport widget pinned above the crumb in the Void chrome
/// (non-immersive only). Two stacked sub-rows:
///
///   1. A 14 dp seek strip — invisible until you look closely; it draws a
///      1 dp track with a filled portion proportional to playback position
///      and accepts horizontal drag / tap-to-seek inside the same hit
///      rectangle.
///   2. A 40 dp icon row — prev / play-pause / next, no labels.
///
/// Total height [transportHeight] is exposed for callers that need to lay
/// out around the strip.
class TransportRow extends StatelessWidget {
  const TransportRow({super.key});

  static const Key prevKey = ValueKey<String>('transport-prev');
  static const Key playKey = ValueKey<String>('transport-play');
  static const Key nextKey = ValueKey<String>('transport-next');
  static const Key seekKey = ValueKey<String>('transport-seek');

  /// Total height of the row (seek strip + icon row). Kept in sync with
  /// the `_transportHeight` constant in `void_screen.dart`.
  static const double transportHeight = 56.0;
  static const double _seekStripHeight = 14.0;
  static const double _iconRowHeight = 42.0;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final dividerColor = palette.divider;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: dividerColor, width: 1)),
      ),
      child: SizedBox(
        height: transportHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(height: _seekStripHeight, child: _SeekStrip()),
            SizedBox(height: _iconRowHeight, child: _IconRow()),
          ],
        ),
      ),
    );
  }
}

/// Draggable / tap-to-seek strip drawn above the transport icons.
class _SeekStrip extends StatelessWidget {
  const _SeekStrip();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final player = context.watch<AudioPlayerProvider>();
    final si = player.songInfo;
    final positionMs = si?.position ?? 0;
    final durationMs = si?.duration ?? 0;
    final hasDuration = durationMs > 0;
    final fraction = hasDuration
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;

    void seekTo(double localX, double width) {
      if (!hasDuration || width <= 0) return;
      final f = (localX / width).clamp(0.0, 1.0);
      final ms = (f * durationMs).round();
      player.seek(Duration(milliseconds: ms));
    }

    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return Listener(
          key: TransportRow.seekKey,
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => seekTo(e.localPosition.dx, width),
          onPointerMove: (e) => seekTo(e.localPosition.dx, width),
          child: CustomPaint(
            painter: _SeekPainter(
              fraction: fraction,
              trackColor: palette.divider,
              fillColor: palette.fgPrimary.withValues(alpha: 0.85),
            ),
            size: Size(width, TransportRow._seekStripHeight),
          ),
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.fraction,
    required this.trackColor,
    required this.fillColor,
  });

  final double fraction;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Bottom-aligned 1 dp hairline so the strip reads as a divider when
    // playback hasn't started yet, with a thicker (1.5 dp) filled portion
    // that mirrors the bottom readonly progress hairline.
    final y = size.height - 1.0;
    final track = Paint()
      ..color = trackColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), track);

    if (fraction > 0) {
      final fill = Paint()
        ..color = fillColor
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.square
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width * fraction, y),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeekPainter old) =>
      old.fraction != fraction ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor;
}

class _IconRow extends StatelessWidget {
  const _IconRow();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final player = context.watch<AudioPlayerProvider>();
    final glyphColor = palette.fgPrimary.withValues(alpha: 0.7);
    final isPlaying = player.isPlaying;

    Widget button({
      required Key key,
      required IconData icon,
      required VoidCallback onTap,
      required String label,
    }) {
      return Expanded(
        child: Semantics(
          label: label,
          button: true,
          child: InkResponse(
            key: key,
            onTap: onTap,
            radius: 28,
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
          key: TransportRow.prevKey,
          icon: Icons.skip_previous_rounded,
          onTap: player.previous,
          label: 'previous',
        ),
        button(
          key: TransportRow.playKey,
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: player.playPause,
          label: isPlaying ? 'pause' : 'play',
        ),
        button(
          key: TransportRow.nextKey,
          icon: Icons.skip_next_rounded,
          onTap: player.next,
          label: 'next',
        ),
      ],
    );
  }
}
