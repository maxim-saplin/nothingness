import 'package:path/path.dart' as p;

import '../models/audio_track.dart';

class TrackSearchIndex {
  TrackSearchIndex([Iterable<AudioTrack> tracks = const <AudioTrack>[]]) {
    replace(tracks);
  }

  final List<_TrackSearchEntry> _entries = [];

  int get length => _entries.length;

  void replace(Iterable<AudioTrack> tracks) {
    _entries.clear();
    final seenPaths = <String>{};
    for (final track in tracks) {
      if (!seenPaths.add(track.path)) continue;
      _entries.add(_TrackSearchEntry(track));
    }
  }

  List<AudioTrack> search(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return const <AudioTrack>[];

    final matches = <AudioTrack>[];
    for (final entry in _entries) {
      if (entry.title.contains(lower) ||
          entry.artist.contains(lower) ||
          entry.basename.contains(lower)) {
        matches.add(entry.track);
      }
    }
    return matches;
  }
}

class _TrackSearchEntry {
  _TrackSearchEntry(this.track)
      : title = track.title.toLowerCase(),
        artist = track.artist.toLowerCase(),
        basename = _basename(track.path).toLowerCase();

  final AudioTrack track;
  final String title;
  final String artist;
  final String basename;
}

String _basename(String path) {
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.last;
  }
  return p.basename(path);
}
