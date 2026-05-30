import 'package:path/path.dart' as p;

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

    final roots = deviceRoots
        .map(_normalizeDir)
        .where((r) => r.isNotEmpty && r.startsWith('/'))
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length)); // longest-first

    final byDevice = <String, List<String>>{};
    for (final song in songs) {
      final root = _matchDeviceRoot(roots, song.path);
      if (root == null) continue;
      final parent = _parentDir(song.path);
      if (parent.isEmpty) continue;
      byDevice.putIfAbsent(root, () => []).add(parent);
    }

    final sections = <SmartRootSection>[];
    for (final entry in byDevice.entries) {
      final candidates = _candidatesForDevice(root: entry.key, songDirs: entry.value);
      // Music-only contract: never fall back to the bare device root. With no
      // candidates (or over the cap) the device is omitted, showing an empty
      // smart-roots view rather than the whole file system.
      if (candidates.isEmpty || candidates.length > maxEntriesPerDevice) continue;
      sections.add(SmartRootSection(deviceRoot: entry.key, entries: candidates));
    }
    sections.sort((a, b) => a.deviceRoot.compareTo(b.deviceRoot));
    return sections;
  }

  static String _normalizeDir(String path) =>
      path.endsWith('/') && path.isNotEmpty ? path.substring(0, path.length - 1) : path;

  static String _parentDir(String path) {
    final trimmed = _normalizeDir(path);
    final i = trimmed.lastIndexOf('/');
    return i <= 0 ? '' : trimmed.substring(0, i);
  }

  static String? _matchDeviceRoot(List<String> rootsLongestFirst, String songPath) {
    for (final root in rootsLongestFirst) {
      if (songPath == root || songPath.startsWith('$root/')) return root;
    }
    return null;
  }

  static List<String> _candidatesForDevice({
    required String root,
    required List<String> songDirs,
  }) {
    // Partition by first segment under root; per partition, trie the
    // audio-bearing dirs and pick the first meaningful branching folder.
    final partitions = <String, List<List<String>>>{};
    for (final absDir in songDirs) {
      if (absDir == root || !absDir.startsWith('$root/')) continue;
      final segs = absDir
          .substring(root.length + 1)
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();
      if (segs.isEmpty) continue;
      partitions.putIfAbsent(segs.first, () => []).add(segs);
    }

    final candidates = <String>{};
    for (final entry in partitions.entries) {
      if (entry.value.isEmpty) continue;
      final segs = _firstBranchingFolder(partitionKey: entry.key, segLists: entry.value);
      candidates.add('$root/${segs.join('/')}');
    }
    return _removeRedundantPaths(candidates.toList());
  }

  static List<String> _removeRedundantPaths(List<String> paths) {
    final sorted = paths.toList()..sort((a, b) => a.length.compareTo(b.length));
    final filtered = <String>[];
    for (final path in sorted) {
      final isChild = filtered.any((parent) => path == parent || path.startsWith('$parent/'));
      if (!isChild) filtered.add(path);
    }
    return filtered..sort();
  }

  static List<String> _firstBranchingFolder({
    required String partitionKey,
    required List<List<String>> segLists,
  }) {
    // Trie where each node tracks whether audio exists in its subtree (segs
    // already includes partitionKey as the first segment).
    final root = _TrieNode();
    for (final segs in segLists) {
      root.addPath(segs);
    }

    // Single-chain (no branching): prefer the partition root.
    if (!root.hasAnyBranching()) return [partitionKey];

    // Keep near-root branching (avoid overly-specific entries like Music/Rock);
    // descend long prefixes (e.g. Android/media/.../Music/CDs).
    const minDepthToDescend = 3;
    final partitionNode = root.children[partitionKey];
    if (root.depthToFirstBranching(partitionKey) < minDepthToDescend ||
        partitionNode == null) {
      return [partitionKey];
    }

    // Descend the single audio-bearing child until the first branching point.
    final chosen = <String>[partitionKey];
    var node = partitionNode;
    while (true) {
      final children = node.audioBearingChildren();
      if (children.length != 1) return chosen; // branch or dead-end
      chosen.add(children.single);
      node = node.children[children.single]!;
    }
  }
}

class _TrieNode {
  final Map<String, _TrieNode> children = {};
  bool hasAudioInSubtree = false;

  void addPath(List<String> segments) {
    var node = this..hasAudioInSubtree = true;
    for (final seg in segments) {
      node = node.children.putIfAbsent(seg, _TrieNode.new)..hasAudioInSubtree = true;
    }
  }

  List<String> audioBearingChildren() => [
    for (final e in children.entries)
      if (e.value.hasAudioInSubtree) e.key,
  ]..sort();

  bool hasAnyBranching() =>
      audioBearingChildren().length >= 2 ||
      children.values.any((c) => c.hasAnyBranching());

  int depthToFirstBranching(String firstSegment) {
    // Edges from firstSegment to the first node with >=2 audio-bearing
    // children; large value if none.
    var node = children[firstSegment];
    if (node == null) return 1 << 30;
    var depth = 0;
    while (true) {
      final children = node!.audioBearingChildren();
      if (children.length >= 2) return depth;
      if (children.isEmpty) return 1 << 30;
      node = node.children[children.single];
      if (node == null) return 1 << 30;
      depth++;
    }
  }
}

/// Presentation-layer label for an Android smart-root entry. [display] is what
/// the user reads; the optional [subtitle] is the dim path / parent hint shown
/// underneath (null means no second line).
class SmartRootLabel {
  const SmartRootLabel({required this.display, this.subtitle});

  final String display;
  final String? subtitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartRootLabel && display == other.display && subtitle == other.subtitle;

  @override
  int get hashCode => Object.hash(display, subtitle);

  @override
  String toString() => 'SmartRootLabel(display: $display, subtitle: $subtitle)';
}

/// Well-known top-level audio folder basenames on Android. When a smart-root
/// path ends in one of these, the basename is a strong enough label on its
/// own — the parent path becomes the dim subtitle.
const Set<String> _wellKnownBasenamesLower = {
  'music',
  'download',
  'downloads',
  'podcasts',
  'audiobooks',
  'recordings',
  'ringtones',
  'notifications',
  'alarms',
};

/// Maps an absolute Android path to a friendly [SmartRootLabel].
///
/// Rules (in order):
/// 1. `/storage/emulated/0` -> `Internal`, no subtitle.
/// 2. `/storage/<UUID>` (single-segment device root) -> `USB` if [isRemovable]
///    else `Removable`.
/// 3. Trailing well-known basename -> the basename verbatim (case-preserved),
///    with parent context as subtitle.
/// 4. Otherwise -> the basename, with the full path as a dim subtitle.
SmartRootLabel labelForPath(String absolutePath, {bool isRemovable = false}) {
  final path = _stripTrailingSlash(absolutePath);
  if (path.isEmpty) return const SmartRootLabel(display: '/');

  // Device-root cases first.
  if (path == '/storage/emulated/0') return const SmartRootLabel(display: 'Internal');
  if (_isStorageDeviceRoot(path)) {
    return SmartRootLabel(display: isRemovable ? 'USB' : 'Removable');
  }

  final base = p.basename(path);
  if (base.isEmpty) return SmartRootLabel(display: path);

  // Trailing well-known basename: subtitle is the full path when directly under
  // a device root, else the parent basename (disambiguates two `Music` entries).
  if (_wellKnownBasenamesLower.contains(base.toLowerCase())) {
    final parent = _stripTrailingSlash(p.dirname(path));
    if (parent.isEmpty || parent == '/' || _isDeviceRoot(parent)) {
      return SmartRootLabel(display: base, subtitle: path);
    }
    final parentBase = p.basename(parent);
    return SmartRootLabel(display: base, subtitle: parentBase.isEmpty ? path : parentBase);
  }

  return SmartRootLabel(display: base, subtitle: path);
}

/// Display string used when a device contributes more entries than the cap
/// and we fall back to the bare device root. Friendlier than the raw path.
String fallbackDeviceLabel(String deviceRoot) =>
    '${labelForPath(deviceRoot).display} — all music';

/// Collapses near-duplicate entries that differ only by a case-insensitive
/// whitespace tweak or by `Music` vs `music`. Preserves the first occurrence
/// (case-preserved) and discards subsequent duplicates.
List<T> dedupeSmartRoots<T>(List<T> entries, String Function(T) keyFor) {
  final seen = <String>{};
  return [
    for (final entry in entries)
      if (seen.add(_canonicalKey(keyFor(entry)))) entry,
  ];
}

/// Collapse whitespace + lower-case so `Music`/`music`/`Music ` map together.
String _canonicalKey(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

String _stripTrailingSlash(String path) =>
    path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;

/// `true` for a single-segment mount under `/storage` other than
/// `/storage/emulated/0` (e.g. `/storage/ABCD-1234`, `/storage/SD_CARD`).
bool _isStorageDeviceRoot(String path) {
  if (!path.startsWith('/storage/')) return false;
  final rest = path.substring('/storage/'.length);
  return rest.isNotEmpty && !rest.contains('/');
}

bool _isDeviceRoot(String path) =>
    path == '/storage/emulated/0' || _isStorageDeviceRoot(path);
