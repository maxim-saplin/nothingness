import 'package:flutter/material.dart';
import '../models/song_info.dart';
import 'retro_ticker.dart';

class RetroLcdDisplay extends StatelessWidget {
  final SongInfo? songInfo;
  final String fontFamily;
  final Color textColor;

  const RetroLcdDisplay({
    super.key,
    required this.songInfo,
    this.fontFamily = 'Press Start 2P',
    this.textColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate responsive font sizes based on available height
        final h = constraints.maxHeight;
        final titleSize = h * 0.22;
        final artistSize = h * 0.18;
        final timeSize = h * 0.15;

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
            // Title
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
            // Artist
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
            // Time
            _buildTimeDisplay(timeSize),
          ],
        );
      },
    );
  }

  Widget _buildTimeDisplay(double fontSize) {
    final position = Duration(milliseconds: songInfo!.position);
    final duration = Duration(milliseconds: songInfo!.duration);

    final posStr = _formatDuration(position);
    final durStr = _formatDuration(duration);

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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours > 0 ? duration.inHours : 0)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
