import 'package:flutter/material.dart';
import '../models/song_info.dart';
import 'retro_ticker.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// `m:ss`, or `h:mm:ss` for durations ≥ 1 h (no leading-zero hour). Negative
/// values clamp to zero. Used by the hero seek HUD.
String formatClock(int ms) {
  final d = Duration(milliseconds: ms < 0 ? 0 : ms);
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (d.inHours > 0) return '${d.inHours}:${_two(m)}:${_two(s)}';
  return '$m:${_two(s)}';
}

/// `hh:mm:ss` with the hours field always padded (and shown as `00` below an
/// hour). Used by the retro LCD readout.
String formatLcdDuration(Duration duration) {
  final h = duration.inHours > 0 ? duration.inHours : 0;
  return '${_two(h)}:${_two(duration.inMinutes.remainder(60))}'
      ':${_two(duration.inSeconds.remainder(60))}';
}

class RetroLcdDisplay extends StatelessWidget {
  final SongInfo? songInfo;
  final String fontFamily;
  final Color textColor;

  /// B-041: multiplier on the LCD font sizes (still derived from the LCD rect height) so Polo participates in the per-screen text-size control.
  final double textScale;

  const RetroLcdDisplay({
    super.key,
    required this.songInfo,
    this.fontFamily = 'Press Start 2P',
    this.textColor = Colors.black,
    this.textScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive font sizes from available height, scaled by the per-screen multiplier (B-041).
        final h = constraints.maxHeight;
        final titleSize = h * 0.22 * textScale;
        final artistSize = h * 0.18 * textScale;
        final timeSize = h * 0.15 * textScale;

        if (songInfo == null) {
          return Center(
            child: Text(
              'NO SIGNAL',
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: titleSize,
                color: textColor,
              ),
            ),
          );
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            RetroTicker(
              text: songInfo!.title,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
                color: textColor,
                height: 1.0,
              ),
            ),
            Text(
              songInfo!.artist,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: artistSize,
                height: 1.0,
                color: textColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            _buildTimeDisplay(timeSize),
          ],
        );
      },
    );
  }

  Widget _buildTimeDisplay(double fontSize) {
    final posStr = formatLcdDuration(Duration(milliseconds: songInfo!.position));
    final durStr = formatLcdDuration(Duration(milliseconds: songInfo!.duration));
    return Text(
      '$posStr / $durStr',
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        letterSpacing: 2.0,
        color: textColor,
      ),
    );
  }
}
