import 'audio_track.dart';

class SongInfo {
  final AudioTrack track;
  final bool isPlaying;
  final int position;
  final int duration;

  const SongInfo({
    required this.track,
    required this.isPlaying,
    required this.position,
    required this.duration,
  });

  // Convenience getters for backward compatibility
  String get title => track.title;
  String get artist => track.artist;
  String get album => ''; // Not stored in AudioTrack currently

  factory SongInfo.fromMap(Map<dynamic, dynamic> map) {
    // Create AudioTrack first, then wrap in SongInfo
    // Note: path may be empty for external players (e.g., Android MediaSessionService)
    final track = AudioTrack(
      path: map['path'] as String? ?? '',
      title: map['title'] as String? ?? 'Unknown',
      artist: map['artist'] as String? ?? '',
    );
    return SongInfo(
      track: track,
      isPlaying: map['isPlaying'] as bool? ?? false,
      position: (map['position'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
    );
  }
}

