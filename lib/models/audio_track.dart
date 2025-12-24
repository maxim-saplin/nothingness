import 'package:hive/hive.dart';

/// Lightweight track metadata used for queue persistence.
@HiveType(typeId: AudioTrackAdapter.kTypeId)
class AudioTrack {
  const AudioTrack({
    required this.path,
    required this.title,
    this.artist = 'Local File',
    this.duration,
  });

  final String path;
  final String title;
  final String artist;
  final Duration? duration;

  AudioTrack copyWith({
    String? path,
    String? title,
    String? artist,
    Duration? duration,
  }) {
    return AudioTrack(
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
    );
  }
}

class AudioTrackAdapter extends TypeAdapter<AudioTrack> {
  static const int kTypeId = 1;

  @override
  int get typeId => AudioTrackAdapter.kTypeId;

  @override
  AudioTrack read(BinaryReader reader) {
    final path = reader.readString();
    final title = reader.readString();
    final artist = reader.readString();
    final hasDuration = reader.readBool();
    final durationMs = hasDuration ? reader.readInt() : null;
    return AudioTrack(
      path: path,
      title: title,
      artist: artist,
      duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
    );
  }

  @override
  void write(BinaryWriter writer, AudioTrack obj) {
    writer
      ..writeString(obj.path)
      ..writeString(obj.title)
      ..writeString(obj.artist)
      ..writeBool(obj.duration != null)
      ..writeInt(obj.duration?.inMilliseconds ?? 0);
  }
}
