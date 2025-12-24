import 'package:flutter/material.dart';

import '../models/song_info.dart';

class SongInfoDisplay extends StatelessWidget {
  final SongInfo? songInfo;
  final Color? textColor;

  const SongInfoDisplay({
    super.key,
    required this.songInfo,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (songInfo == null) {
      return const SizedBox.shrink();
    }

    return _buildSongInfo(songInfo!);
  }

  Widget _buildSongInfo(SongInfo song) {
    final titleColor = textColor ?? Colors.white;
    final artistColor = textColor?.withValues(alpha: 0.6) ?? Colors.white60;
    final albumColor = textColor?.withValues(alpha: 0.3) ?? Colors.white30;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Song title
          Text(
            song.title,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: titleColor,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Artist
          Text(
            song.artist,
            style: TextStyle(fontSize: 18, color: artistColor),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (song.album.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              song.album,
              style: TextStyle(fontSize: 14, color: albumColor),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
