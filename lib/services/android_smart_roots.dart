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

      final entriesForDevice = candidates.isEmpty
          ? <String>[root]
          : (candidates.length > maxEntriesPerDevice
                ? <String>[root]
                : candidates);

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
    // Partition by first segment under root. For each partition, build a trie
    // of audio-bearing directories and pick the first meaningful branching folder.
    final Map<String, List<List<String>>> partitionToDirSegs =
        <String, List<List<String>>>{};

    for (final absDir in songDirs) {
      if (absDir == root) continue; // ignore files directly under device root
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
      final partitionKey = entry.key;
      final segLists = entry.value;
      if (segLists.isEmpty) continue;

      final candidateSegs = _firstBranchingFolder(
        partitionKey: partitionKey,
        segLists: segLists,
      );
      final candidate = '$root/${candidateSegs.join('/')}';
      candidates.add(candidate);
    }

    return _removeRedundantPaths(candidates.toList());
  }

  static List<String> _removeRedundantPaths(List<String> paths) {
    final sorted = paths.toList()..sort((a, b) => a.length.compareTo(b.length));
    final filtered = <String>[];
    for (final path in sorted) {
      final isChildOfExisting = filtered.any((parent) {
        if (path == parent) return true;
        return path.startsWith('$parent/');
      });
      if (!isChildOfExisting) filtered.add(path);
    }
    filtered.sort((a, b) => a.compareTo(b));
    return filtered;
  }

  static List<String> _firstBranchingFolder({
    required String partitionKey,
    required List<List<String>> segLists,
  }) {
    // Build a trie where each node tracks whether audio exists in its subtree.
    final root = _TrieNode();
    for (final segs in segLists) {
      // segs already includes partitionKey as first segment.
      root.addPath(segs);
    }

    // If there's no branching anywhere (single-chain), prefer the partition root.
    if (!root.hasAnyBranching()) {
      return [partitionKey];
    }

    // If the first branching point is very near the partition root (e.g. Music/Rock),
    // keep the partition root to avoid overly-specific entries that don't save much.
    // But if the chain before branching is long (e.g. Android/media/.../Music/CDs),
    // descend to the first branching folder to skip the boring prefix.
    const minDepthToDescend = 3;
    final depthToFirstBranching = root.depthToFirstBranching(partitionKey);
    if (depthToFirstBranching < minDepthToDescend) {
      return [partitionKey];
    }

    // Walk down from partition root following the only audio-bearing child while
    // we haven't hit a meaningful branching point.
    final chosen = <String>[];
    _TrieNode node = root;

    // Move into the partition root node first.
    final partitionNode = node.children[partitionKey];
    if (partitionNode == null) return [partitionKey];
    chosen.add(partitionKey);
    node = partitionNode;

    while (true) {
      final audioChildren = node.audioBearingChildren();
      if (audioChildren.length >= 2) {
        // First branching folder.
        return chosen;
      }

      if (audioChildren.isEmpty) {
        // Shouldn't happen for audio-bearing paths; be safe.
        return chosen;
      }

      // Exactly one audio-bearing child: continue descending, but only if that
      // child also has branching somewhere below; otherwise stop here to avoid
      // overly-deep single-chain entries like Music/Rock.
      final nextEntry = audioChildren.single;
      final nextNode = node.children[nextEntry]!;

      chosen.add(nextEntry);
      node = nextNode;
    }
  }
}

class _TrieNode {
  final Map<String, _TrieNode> children = <String, _TrieNode>{};
  bool hasAudioInSubtree = false;

  void addPath(List<String> segments) {
    _TrieNode node = this;
    node.hasAudioInSubtree = true;
    for (final seg in segments) {
      node = node.children.putIfAbsent(seg, _TrieNode.new);
      node.hasAudioInSubtree = true;
    }
  }

  List<String> audioBearingChildren() {
    final result = <String>[];
    for (final entry in children.entries) {
      if (entry.value.hasAudioInSubtree) result.add(entry.key);
    }
    result.sort();
    return result;
  }

  bool hasAnyBranching() {
    final audioChildrenCount = audioBearingChildren().length;
    if (audioChildrenCount >= 2) return true;
    for (final child in children.values) {
      if (child.hasAnyBranching()) return true;
    }
    return false;
  }

  int depthToFirstBranching(String firstSegment) {
    // Returns number of edges from the firstSegment node to the first node that has
    // >=2 audio-bearing children. If none found, returns a large value.
    final start = children[firstSegment];
    if (start == null) return 1 << 30;

    int depth = 0;
    _TrieNode node = start;
    while (true) {
      final count = node.audioBearingChildren().length;
      if (count >= 2) return depth;
      if (count == 0) return 1 << 30;
      // count == 1
      final nextKey = node.audioBearingChildren().single;
      final next = node.children[nextKey];
      if (next == null) return 1 << 30;
      depth += 1;
      node = next;
    }
  }
}
