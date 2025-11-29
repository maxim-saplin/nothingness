class SongInfo {
  final String title;
  final String artist;
  final String album;
  final bool isPlaying;
  final int position;
  final int duration;

  const SongInfo({
    required this.title,
    required this.artist,
    required this.album,
    required this.isPlaying,
    required this.position,
    required this.duration,
  });

  factory SongInfo.fromMap(Map<dynamic, dynamic> map) {
    return SongInfo(
      title: map['title'] as String? ?? 'Unknown',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      album: map['album'] as String? ?? '',
      isPlaying: map['isPlaying'] as bool? ?? false,
      position: (map['position'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
    );
  }
}

