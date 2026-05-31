import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';

class LibraryService {
  LibraryService._internal();
  static final LibraryService _instance = LibraryService._internal();
  factory LibraryService() => _instance;

  static const String _boxName = 'libraryBox';
  static const String _rootsKey = 'roots';
  static const String _lastScanTimestampKey = 'lastScanTimestamp';

  /// Desktop OSes use a folder-backed library with persisted roots. macOS
  /// additionally wraps each root in a security-scoped bookmark; Linux has
  /// no sandbox so a raw path round-trips.
  static bool get _isDesktopRoots => Platform.isMacOS || Platform.isLinux;

  final SecureBookmarks? _secureBookmarks =
      Platform.isMacOS ? SecureBookmarks() : null;

  Box<dynamic>? _box;

  /// Map of path -> bookmark string.
  final ValueNotifier<Map<String, String>> rootsNotifier = ValueNotifier({});

  Future<void> init() async {
    _box = await Hive.openBox<dynamic>(_boxName);
    final stored = _box!.get(_rootsKey);
    if (stored is Map) {
      final roots = Map<String, String>.from(stored);
      rootsNotifier.value = roots;
      if (Platform.isMacOS) {
        for (final entry in roots.entries) {
          try {
            await _secureBookmarks!.resolveBookmark(entry.value);
            await _secureBookmarks
                .startAccessingSecurityScopedResource(File(entry.key));
            debugPrint('Resolved bookmark for ${entry.key}');
          } catch (e) {
            debugPrint('Failed to resolve bookmark for ${entry.key}: $e');
          }
        }
      }
    }
  }

  Future<void> addRoot(String path) async {
    if (!_isDesktopRoots) return;
    try {
      // Linux has no sandbox — store the raw path as the "bookmark" so the
      // persistence schema stays uniform across desktop OSes.
      final bookmark =
          Platform.isMacOS ? await _secureBookmarks!.bookmark(File(path)) : path;
      rootsNotifier.value = {...rootsNotifier.value, path: bookmark};
      await _persistRoots();
    } catch (e) {
      debugPrint('Failed to add root $path: $e');
    }
  }

  Future<void> removeRoot(String path) async {
    final roots = Map<String, String>.from(rootsNotifier.value);
    if (roots.remove(path) != null) {
      rootsNotifier.value = roots;
      await _persistRoots();
    }
  }

  Future<void> _persistRoots() async =>
      _box?.put(_rootsKey, rootsNotifier.value);

  /// Store the last scan timestamp (Android only).
  Future<void> setLastScanTimestamp(int timestampMs) async {
    if (Platform.isAndroid) await _box?.put(_lastScanTimestampKey, timestampMs);
  }

  /// Get the last scan timestamp (Android only).
  int? getLastScanTimestamp() =>
      Platform.isAndroid ? _box?.get(_lastScanTimestampKey) as int? : null;

  /// Call this when the app is closing to release resources.
  Future<void> dispose() async {
    if (!Platform.isMacOS) return;
    for (final path in rootsNotifier.value.keys) {
      try {
        await _secureBookmarks!
            .stopAccessingSecurityScopedResource(File(path));
      } catch (e) {
        debugPrint('Error stopping access for $path: $e');
      }
    }
  }
}
