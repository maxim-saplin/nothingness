import 'dart:math';

import 'library_browser.dart';

class SmartRootSection {
  const SmartRootSection({required this.deviceRoot, required this.entries});

  /// The mount point / device root, e.g. `/storage/emulated/0` or `/storage/ABCD-1234`.
  final String deviceRoot;

  /// Absolute folder paths to show as entry points for this device.
  final List<String> entries;
}

/// Pure helper to compute “smart roots” for Android folder browsing from MediaStore paths.
class AndroidSmartRoots {
  static List<SmartRootSection> compute({
    required List<String> deviceRoots,
    required List<LibrarySong> songs,
    int maxEntriesPerDevice = 5,
  }) {
    if (deviceRoots.isEmpty || songs.isEmpty) return const [];

    final normalizedRoots =
        deviceRoots
            .map(_normalizeDir)
            .where((r) => r.isNotEmpty && r.startsWith('/'))
            .toList()
          ..sort(
            (a, b) => b.length.compareTo(a.length),
          ); // longest-first for matching

    final Map<String, List<String>> deviceToSongDirs = <String, List<String>>{};

    for (final song in songs) {
      final songPath = song.path;
      final root = _matchDeviceRoot(normalizedRoots, songPath);
      if (root == null) continue;

      final parentDir = _parentDir(songPath);
      if (parentDir.isEmpty) continue;

      deviceToSongDirs.putIfAbsent(root, () => <String>[]).add(parentDir);
    }

    final sections = <SmartRootSection>[];
    for (final entry in deviceToSongDirs.entries) {
      final root = entry.key;
      final dirs = entry.value;

      final candidates = _candidatesForDevice(root: root, songDirs: dirs);

      final entriesForDevice = (candidates.length > maxEntriesPerDevice)
          ? <String>[root]
          : candidates;

      sections.add(
        SmartRootSection(deviceRoot: root, entries: entriesForDevice),
      );
    }

    sections.sort((a, b) => a.deviceRoot.compareTo(b.deviceRoot));
    return sections;
  }

  static String _normalizeDir(String path) {
    if (path.isEmpty) return path;
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  static String _parentDir(String path) {
    final trimmed = _normalizeDir(path);
    final lastSlash = trimmed.lastIndexOf('/');
    if (lastSlash <= 0) return '';
    return trimmed.substring(0, lastSlash);
  }

  static String? _matchDeviceRoot(
    List<String> rootsLongestFirst,
    String songPath,
  ) {
    for (final root in rootsLongestFirst) {
      if (songPath == root) return root;
      if (songPath.startsWith('$root/')) return root;
    }
    return null;
  }

  static List<String> _candidatesForDevice({
    required String root,
    required List<String> songDirs,
  }) {
    // Partition by first segment under root, but compute deepest common folder per partition.
    final Map<String, List<List<String>>> partitionToDirSegs =
        <String, List<List<String>>>{};

    for (final absDir in songDirs) {
      if (absDir == root) {
        // Song directly under device root.
        partitionToDirSegs
            .putIfAbsent('', () => <List<String>>[])
            .add(const []);
        continue;
      }

      if (!absDir.startsWith('$root/')) continue;

      final rel = absDir.substring(root.length + 1);
      if (rel.isEmpty) continue;

      final segs = rel.split('/').where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) continue;

      final partitionKey = segs.first;
      partitionToDirSegs
          .putIfAbsent(partitionKey, () => <List<String>>[])
          .add(segs);
    }

    final candidates = <String>{};

    for (final entry in partitionToDirSegs.entries) {
      final segLists = entry.value;
      if (segLists.isEmpty) continue;

      final lcaSegs = _commonPrefix(segLists);
      final effectiveSegs = _clampCandidateSegments(lcaSegs);
      final candidate = (effectiveSegs.isEmpty)
          ? root
          : '$root/${effectiveSegs.join('/')}';
      candidates.add(candidate);
    }

    final deduped = candidates.toList()
      ..sort((a, b) => a.length.compareTo(b.length));

    // Remove redundancies: if `/a/b` exists, drop `/a/b/c`.
    final filtered = <String>[];
    for (final path in deduped) {
      final isChildOfExisting = filtered.any((parent) {
        if (path == parent) return true;
        return path.startsWith('$parent/');
      });
      if (!isChildOfExisting) filtered.add(path);
    }

    filtered.sort((a, b) => a.compareTo(b));
    return filtered;
  }

  static List<String> _commonPrefix(List<List<String>> lists) {
    if (lists.isEmpty) return const [];
    if (lists.length == 1) return lists.first;

    final minLen = lists.map((l) => l.length).fold<int>(1 << 30, min);
    final prefix = <String>[];

    for (var i = 0; i < minLen; i++) {
      final value = lists.first[i];
      final allSame = lists.every((l) => l[i] == value);
      if (!allSame) break;
      prefix.add(value);
    }

    return prefix;
  }

  /// Heuristic: keep candidates near the top-level to avoid over-deep entries.
  ///
  /// - Always keep at least the first segment (e.g. `Music`, `Downloads`).
  /// - Allow a second segment only for known cases that reduce clicks meaningfully
  ///   without exploding the list (e.g. `Downloads/Music`).
  static List<String> _clampCandidateSegments(List<String> lcaSegs) {
    if (lcaSegs.isEmpty) return const [];
    if (lcaSegs.length == 1) return lcaSegs;

    final first = lcaSegs[0];
    final second = lcaSegs[1];
    if (_isPreferredSecondSegment(second)) {
      return [first, second];
    }
    return [first];
  }

  static bool _isPreferredSecondSegment(String segment) {
    final s = segment.toLowerCase();
    return s == 'music';
  }
}
