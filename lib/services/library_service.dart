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

  final SecureBookmarks? _secureBookmarks =
      Platform.isMacOS ? SecureBookmarks() : null;
  
  Box<dynamic>? _box;
  
  // Map of path -> bookmark string
  final ValueNotifier<Map<String, String>> rootsNotifier = 
      ValueNotifier<Map<String, String>>({});

  Future<void> init() async {
    _box = await Hive.openBox<dynamic>(_boxName);
    await _restoreRoots();
  }

  Future<void> addRoot(String path) async {
    if (!Platform.isMacOS) return;
    
    try {
      final bookmark = await _secureBookmarks!.bookmark(File(path));
      final currentRoots = Map<String, String>.from(rootsNotifier.value);
      currentRoots[path] = bookmark;
      rootsNotifier.value = currentRoots;
      await _persistRoots();
    } catch (e) {
      debugPrint('Failed to create bookmark for $path: $e');
    }
  }

  Future<void> removeRoot(String path) async {
    final currentRoots = Map<String, String>.from(rootsNotifier.value);
    if (currentRoots.remove(path) != null) {
      rootsNotifier.value = currentRoots;
      await _persistRoots();
    }
  }

  Future<void> _restoreRoots() async {
    if (_box == null) return;
    
    final storedRoots = _box!.get(_rootsKey);
    if (storedRoots is Map) {
      final roots = Map<String, String>.from(storedRoots);
      rootsNotifier.value = roots;
      
      if (Platform.isMacOS) {
        await _resolveBookmarks(roots);
      }
    }
  }

  Future<void> _resolveBookmarks(Map<String, String> roots) async {
    for (final entry in roots.entries) {
      try {
        await _secureBookmarks!.resolveBookmark(entry.value);
        await _secureBookmarks.startAccessingSecurityScopedResource(File(entry.key));
        debugPrint('Resolved bookmark for ${entry.key}');
      } catch (e) {
        debugPrint('Failed to resolve bookmark for ${entry.key}: $e');
      }
    }
  }

  Future<void> _persistRoots() async {
    if (_box == null) return;
    await _box!.put(_rootsKey, rootsNotifier.value);
  }

  /// Store the last scan timestamp (Android only)
  Future<void> setLastScanTimestamp(int timestampMs) async {
    if (!Platform.isAndroid || _box == null) return;
    await _box!.put(_lastScanTimestampKey, timestampMs);
  }

  /// Get the last scan timestamp (Android only)
  int? getLastScanTimestamp() {
    if (!Platform.isAndroid || _box == null) return null;
    return _box!.get(_lastScanTimestampKey) as int?;
  }
  
  /// Call this when the app is closing to release resources
  Future<void> dispose() async {
    if (Platform.isMacOS) {
      for (final path in rootsNotifier.value.keys) {
        try {
          await _secureBookmarks!.stopAccessingSecurityScopedResource(File(path));
        } catch (e) {
          debugPrint('Error stopping access for $path: $e');
        }
      }
    }
  }
}
