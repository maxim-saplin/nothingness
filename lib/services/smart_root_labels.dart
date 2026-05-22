import 'package:path/path.dart' as p;

/// Presentation-layer label for an Android smart-root entry.
///
/// Pure UI sugar over absolute paths produced by [AndroidSmartRoots] and the
/// device-root mounts surfaced by `LibraryController`. The display string is
/// what the user reads; the optional [subtitle] is the dim path / parent hint
/// shown underneath. A null [subtitle] means "no second line" (e.g. the path
/// already equals the display).
class SmartRootLabel {
  const SmartRootLabel({required this.display, this.subtitle});

  final String display;
  final String? subtitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartRootLabel &&
          display == other.display &&
          subtitle == other.subtitle;

  @override
  int get hashCode => Object.hash(display, subtitle);

  @override
  String toString() =>
      'SmartRootLabel(display: $display, subtitle: $subtitle)';
}

/// Well-known top-level audio folder basenames on Android. When a smart-root
/// path ends in one of these, the basename is a strong enough label on its
/// own — the parent path becomes the dim subtitle.
const Set<String> _wellKnownBasenamesLower = <String>{
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
/// 2. `/storage/<UUID>` (device root, single segment under `/storage`) ->
///    `USB` / `SD card` based on [isRemovable], else `Removable`.
/// 3. Trailing well-known basename (`Music`, `Download`, `Downloads`,
///    `Podcasts`, `Audiobooks`, `Recordings`, `Ringtones`, `Notifications`,
///    `Alarms`) -> the basename verbatim (case-preserved from the path), with
///    the parent path as subtitle when there's parent context worth showing.
/// 4. Otherwise -> the basename, with the full path as a dim subtitle.
SmartRootLabel labelForPath(
  String absolutePath, {
  bool isRemovable = false,
}) {
  final path = _stripTrailingSlash(absolutePath);
  if (path.isEmpty) {
    return const SmartRootLabel(display: '/');
  }

  // Device-root cases first.
  if (path == '/storage/emulated/0') {
    return const SmartRootLabel(display: 'Internal');
  }
  if (_isStorageDeviceRoot(path)) {
    final label = isRemovable ? 'USB' : 'Removable';
    return SmartRootLabel(display: label);
  }

  final base = p.basename(path);
  if (base.isEmpty) {
    return SmartRootLabel(display: path);
  }

  // Trailing well-known basename -> friendly display.
  //   - Nested under a non-device-root parent (e.g. /storage/UUID/Nextcloud/Music):
  //     subtitle is the immediate parent basename ("Nextcloud") — enough to
  //     disambiguate two `Music` entries on the same device.
  //   - Directly under a device root (e.g. /storage/emulated/0/Music):
  //     subtitle is the full path so the user still sees where the folder
  //     lives.
  if (_wellKnownBasenamesLower.contains(base.toLowerCase())) {
    final parent = _stripTrailingSlash(p.dirname(path));
    if (parent.isEmpty || parent == '/' || _isDeviceRoot(parent)) {
      return SmartRootLabel(display: base, subtitle: path);
    }
    final parentBase = p.basename(parent);
    return SmartRootLabel(
      display: base,
      subtitle: parentBase.isEmpty ? path : parentBase,
    );
  }

  // Generic case: basename plus full path subtitle.
  return SmartRootLabel(display: base, subtitle: path);
}

/// Display string used when a device contributes more entries than the cap
/// and we fall back to the bare device root. Friendlier than the raw path.
String fallbackDeviceLabel(String deviceRoot) {
  final label = labelForPath(deviceRoot).display;
  return '$label — all music';
}

/// Collapses near-duplicate entries that differ only by a case-insensitive
/// whitespace tweak or by `Music` vs `music`. Preserves the first occurrence
/// (case-preserved) and discards subsequent duplicates.
List<T> dedupeSmartRoots<T>(List<T> entries, String Function(T) keyFor) {
  final seen = <String>{};
  final result = <T>[];
  for (final entry in entries) {
    final canon = _canonicalKey(keyFor(entry));
    if (seen.add(canon)) {
      result.add(entry);
    }
  }
  return result;
}

String _canonicalKey(String raw) {
  // Collapse internal whitespace runs and lower-case so `Music` and `music`,
  // `Music ` and `music`, all map to the same canonical form.
  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return collapsed.toLowerCase();
}

String _stripTrailingSlash(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

/// `true` when [path] is a single-segment mount under `/storage` other than
/// `/storage/emulated/0` (which is handled separately). Matches things like
/// `/storage/ABCD-1234`, `/storage/SD_CARD`, etc.
bool _isStorageDeviceRoot(String path) {
  if (!path.startsWith('/storage/')) return false;
  final rest = path.substring('/storage/'.length);
  if (rest.isEmpty) return false;
  if (rest.contains('/')) return false;
  return true;
}

bool _isDeviceRoot(String path) {
  if (path == '/storage/emulated/0') return true;
  return _isStorageDeviceRoot(path);
}
