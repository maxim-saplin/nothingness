import 'package:flutter/material.dart';
import '../models/song_info.dart';
import 'retro_ticker.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// `m:ss`, or `h:mm:ss` for durations ≥ 1 h (no leading-zero hour). Negative
/// values clamp to zero. Used by the hero seek HUD.
String formatClock(int ms) {
  final d = Duration(milliseconds: ms < 0 ? 0 : ms);
  final m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
  return d.inHours > 0 ? '${d.inHours}:${_two(m)}:${_two(s)}' : '$m:${_two(s)}';
}

/// `hh:mm:ss` with the hours field always padded (and shown as `00` below an
/// hour). Used by the retro LCD readout.
String formatLcdDuration(Duration d) {
  final h = d.inHours > 0 ? d.inHours : 0;
  return '${_two(h)}:${_two(d.inMinutes.remainder(60))}:${_two(d.inSeconds.remainder(60))}';
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
        final song = songInfo;

        if (song == null) {
          return Center(
            child: Text(
              'NO SIGNAL',
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: h * 0.22 * textScale,
                color: textColor,
              ),
            ),
          );
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            RetroTicker(
              text: song.title,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: h * 0.22 * textScale,
                fontWeight: FontWeight.bold,
                color: textColor,
                height: 1.0,
              ),
            ),
            Text(
              song.artist,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: h * 0.18 * textScale,
                height: 1.0,
                color: textColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${formatLcdDuration(Duration(milliseconds: song.position))}'
              ' / ${formatLcdDuration(Duration(milliseconds: song.duration))}',
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: h * 0.15 * textScale,
                letterSpacing: 2.0,
                color: textColor,
              ),
            ),
          ],
        );
      },
    );
  }
}
