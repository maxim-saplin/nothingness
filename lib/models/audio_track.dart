class AudioTrack {
  final String path;
  final String title;
  final String artist;
  final Duration? duration;

  const AudioTrack({
    required this.path,
    required this.title,
    this.artist = 'Local File',
    this.duration,
  });
}
