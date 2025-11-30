import 'package:flutter/material.dart';

import '../models/song_info.dart';

class SongInfoDisplay extends StatelessWidget {
  final SongInfo? songInfo;
  final bool hasNotificationAccess;
  final bool isAndroid;
  final Color? textColor;

  const SongInfoDisplay({
    super.key,
    required this.songInfo,
    required this.hasNotificationAccess,
    required this.isAndroid,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAndroid) {
      return _buildMacOSPreview();
    }

    if (!hasNotificationAccess) {
      return _buildNotificationAccessRequired();
    }

    if (songInfo == null) {
      return _buildNoMusicPlaying();
    }

    return _buildSongInfo(songInfo!);
  }

  Widget _buildMacOSPreview() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            'macOS Preview',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1.5,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Media controls require Android',
            style: TextStyle(fontSize: 16, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationAccessRequired() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 48,
            color: Colors.white30,
          ),
          SizedBox(height: 16),
          Text(
            'Notification Access Required',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white54,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Enable notification access to see currently playing music',
            style: TextStyle(fontSize: 14, color: Colors.white30),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoMusicPlaying() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.music_off_outlined, size: 48, color: Colors.white30),
          SizedBox(height: 16),
          Text(
            'No Music Playing',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white54,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start playing music in any app',
            style: TextStyle(fontSize: 14, color: Colors.white30),
          ),
        ],
      ),
    );
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
