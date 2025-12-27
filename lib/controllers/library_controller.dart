import 'dart:io';

import 'package:external_path/external_path.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/audio_track.dart';
import '../models/log_entry.dart';
import '../services/library_browser.dart';
import '../services/library_service.dart';
import '../services/logging_service.dart';
import '../services/metadata_extractor.dart';

// Static function for isolate execution
Future<List<LibrarySong>> _loadAndroidSongsInIsolate(
  RootIsolateToken rootToken,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  final audioQuery = OnAudioQuery();
  final songs = await audioQuery.querySongs(
    sortType: null,
    orderType: OrderType.ASC_OR_SMALLER,
    uriType: UriType.EXTERNAL,
    ignoreCase: true,
  );
  return songs
      .map((song) => LibrarySong(path: song.data, title: song.title))
      .toList();
}

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.libraryBrowser,
    required this.libraryService,
    OnAudioQuery? audioQuery,
    Future<List<LibrarySong>> Function()? androidSongLoader,
    Future<List<String>> Function()? androidRootsLoader,
  }) : _audioQuery = audioQuery ?? OnAudioQuery(),
       _androidSongLoader = androidSongLoader,
       _androidRootsLoader = androidRootsLoader;

  final LibraryBrowser libraryBrowser;
  final LibraryService libraryService;
  final OnAudioQuery _audioQuery;
  final Future<List<LibrarySong>> Function()? _androidSongLoader;
  final Future<List<String>> Function()? _androidRootsLoader;

  bool isLoading = false;
  bool isScanning = false;
  String? error;
  String? currentPath;
  bool hasPermission = !Platform.isAndroid;
  String? initialAndroidRoot;

  List<LibraryFolder> folders = [];
  List<AudioTrack> tracks = [];
  List<LibrarySong> _androidSongs = [];
  bool _disposed = false;

  Future<void> init() async {
    if (Platform.isAndroid) {
      await _checkAndroidPermission();
      if (hasPermission) {
        // Check if library needs refreshing based on MediaStore timestamp
        final needsRefresh = await _shouldRefreshLibrary();
        if (needsRefresh) {
          // Clear cache to force rescan
          _androidSongs = [];
        }
        await _ensureAndroidSongsLoaded();
        await loadRoot();
      }
    }
  }

  /// Check if library needs refreshing by comparing MediaStore timestamp with cached timestamp
  Future<bool> _shouldRefreshLibrary() async {
    try {
      // Query a small sample of songs to get latest timestamp
      // We'll get the first few and check their timestamps
      final sampleSongs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );

      if (sampleSongs.isEmpty) {
        // No songs in MediaStore, don't refresh
        return false;
      }

      // Find the maximum timestamp across all songs
      int? maxTimestamp;
      for (final song in sampleSongs) {
        final timestamp = (song.dateAdded ?? 0) > (song.dateModified ?? 0)
            ? song.dateAdded
            : song.dateModified;
        if (timestamp != null) {
          maxTimestamp = maxTimestamp == null
              ? timestamp
              : (timestamp > maxTimestamp ? timestamp : maxTimestamp);
        }
      }

      if (maxTimestamp == null) {
        // Can't determine timestamp, don't refresh
        return false;
      }

      final lastScanTimestamp = libraryService.getLastScanTimestamp();
      if (lastScanTimestamp == null) {
        // No cached timestamp, need to scan
        await libraryService.setLastScanTimestamp(maxTimestamp);
        return true;
      }

      // Refresh if MediaStore has newer content
      if (maxTimestamp > lastScanTimestamp) {
        await libraryService.setLastScanTimestamp(maxTimestamp);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error checking library timestamp: $e');
      // On error, don't refresh (use cached data)
      return false;
    }
  }

  Future<void> _checkAndroidPermission() async {
    try {
      final storageStatus = await Permission.storage.status;
      final audioStatus = await Permission.audio.status;
      final micStatus = await Permission.microphone.status;
      hasPermission =
          (storageStatus.isGranted || audioStatus.isGranted) &&
          micStatus.isGranted;
      _safeNotifyListeners();
    } catch (e) {
      debugPrint('Failed to check permissions: $e');
      hasPermission = false;
      _safeNotifyListeners();
    }
  }

  Future<void> requestPermission() async {
    isLoading = true;
    error = null;
    _safeNotifyListeners();

    try {
      final statuses = await [
        Permission.storage,
        Permission.audio,
        Permission.microphone,
      ].request();

      hasPermission =
          (statuses[Permission.storage]!.isGranted ||
              statuses[Permission.audio]!.isGranted) &&
          statuses[Permission.microphone]!.isGranted;

      if (hasPermission) {
        await _ensureAndroidSongsLoaded();
        await loadRoot();
      } else {
        error = 'Storage and microphone permissions are required';
      }
    } catch (e) {
      error = 'Failed to request permission: $e';
    } finally {
      isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> loadRoot() async {
    if (Platform.isAndroid) {
      await _loadAndroidRoot();
    }
  }

  Future<void> loadFolder(String path) async {
    isLoading = true;
    error = null;
    _safeNotifyListeners();

    try {
      if (Platform.isAndroid) {
        await _ensureAndroidSongsLoaded();
        var listing = await libraryBrowser.buildVirtualListing(
          basePath: path,
          songs: _androidSongs,
        );

        // If MediaStore has nothing for this path (common on some automotive/USB mounts),
        // fall back to a direct filesystem listing so users can still browse and play.
        if (listing.folders.isEmpty && listing.tracks.isEmpty) {
          final dir = Directory(path);
          if (await dir.exists()) {
            try {
              final fsListing = await libraryBrowser.listFileSystem(path);
              if (fsListing.folders.isNotEmpty || fsListing.tracks.isNotEmpty) {
                listing = fsListing;
                LoggingService().log(
                  tag: 'Library',
                  message:
                      'Used filesystem fallback for $path (MediaStore empty)',
                );
              }
            } catch (e) {
              LoggingService().log(
                tag: 'Library',
                message: 'Filesystem fallback failed for $path: $e',
                level: LogLevel.error,
              );
            }
          }
        }
        currentPath = listing.path;
        folders = listing.folders;
        tracks = listing.tracks;
      } else {
        final listing = await libraryBrowser.listFileSystem(path);
        currentPath = listing.path;
        folders = listing.folders;
        tracks = listing.tracks;
      }
    } catch (e) {
      error = '$e';
    } finally {
      isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> navigateUp() async {
    if (currentPath == null) return;

    if (Platform.isAndroid &&
        initialAndroidRoot != null &&
        currentPath == initialAndroidRoot) {
      await loadRoot(); // Reload root instead of clearing
      return;
    }

    if (libraryService.rootsNotifier.value.containsKey(currentPath)) {
      _clearListing();
      _safeNotifyListeners();
      return;
    }

    final parent = Directory(currentPath!).parent.path;
    if (parent == currentPath) return;
    await loadFolder(parent);
  }

  Future<List<AudioTrack>> tracksForCurrentPath() async {
    if (currentPath == null) return [];

    if (Platform.isAndroid) {
      await _ensureAndroidSongsLoaded();

      // If the current listing already has tracks (e.g., from filesystem fallback), reuse it.
      if (tracks.isNotEmpty && currentPath != null) {
        final listCopy = List<AudioTrack>.from(tracks);
        listCopy.sort((a, b) => a.title.compareTo(b.title));
        return listCopy;
      }

      final extractor = createMetadataExtractor();
      final filtered = <AudioTrack>[];
      for (final song in _androidSongs.where((song) => song.path.startsWith(currentPath!))) {
        try {
          final track = await extractor.extractMetadata(song.path);
          filtered.add(track);
        } catch (e) {
          // Fallback to song title if extraction fails
          filtered.add(AudioTrack(path: song.path, title: song.title));
        }
      }
      filtered.sort((a, b) => a.title.compareTo(b.title));
      return filtered;
    }

    // For macOS we rely on the file system; use the current listing or let caller recurse.
    return tracks;
  }

  Future<void> refreshLibrary() async {
    if (!Platform.isAndroid || !hasPermission) return;

    isScanning = true;
    error = null;
    _safeNotifyListeners();

    try {
      // Clear cache
      _androidSongs = [];
      // Reload songs
      await _ensureAndroidSongsLoaded();
      // Reload current folder if we have one
      if (currentPath != null) {
        await loadFolder(currentPath!);
      } else {
        await loadRoot();
      }
    } catch (e) {
      error = 'Failed to refresh library: $e';
    } finally {
      isScanning = false;
      _safeNotifyListeners();
    }
  }

  Future<void> _ensureAndroidSongsLoaded() async {
    if (_androidSongs.isNotEmpty) return;
    isScanning = true;
    _safeNotifyListeners();

    try {
      // Run in isolate to avoid blocking UI thread
      final token = RootIsolateToken.instance!;
      _androidSongs = await compute(_loadAndroidSongsInIsolate, token);

      // Update scan timestamp after successful load
      if (_androidSongs.isNotEmpty) {
        try {
          final sampleSongs = await _audioQuery.querySongs(
            sortType: null,
            orderType: OrderType.ASC_OR_SMALLER,
            uriType: UriType.EXTERNAL,
          );
          if (sampleSongs.isNotEmpty) {
            // Find max timestamp
            int? maxTimestamp;
            for (final song in sampleSongs) {
              final timestamp = (song.dateAdded ?? 0) > (song.dateModified ?? 0)
                  ? song.dateAdded
                  : song.dateModified;
              if (timestamp != null) {
                maxTimestamp = maxTimestamp == null
                    ? timestamp
                    : (timestamp > maxTimestamp ? timestamp : maxTimestamp);
              }
            }
            if (maxTimestamp != null) {
              await libraryService.setLastScanTimestamp(maxTimestamp);
            }
          }
        } catch (e) {
          debugPrint('Error updating scan timestamp: $e');
        }
      }
    } catch (e) {
      debugPrint(
        'Error loading songs in isolate, falling back to main thread: $e',
      );
      // Fallback to main thread if isolate fails
      try {
        final loader = _androidSongLoader ?? _defaultAndroidSongLoader;
        _androidSongs = await loader();
      } catch (e2) {
        debugPrint('Error loading songs: $e2');
        error = 'Failed to load songs: $e2';
      }
    } finally {
      isScanning = false;
      _safeNotifyListeners();
    }
  }

  Future<List<LibrarySong>> _defaultAndroidSongLoader() async {
    final songs = await _audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    return songs
        .map((song) => LibrarySong(path: song.data, title: song.title))
        .toList();
  }

  Future<void> _loadAndroidRoot() async {
    try {
      final roots = await (_androidRootsLoader ?? _defaultAndroidRootsLoader)();
      if (roots.isNotEmpty) {
        // Prefer a shared /storage root when multiple mount points exist (e.g., internal + USB),
        // so users can navigate to both from a single root view.
        const storageRoot = '/storage';
        final bool hasStorageMounts = roots.any(
          (r) => r.startsWith('$storageRoot/'),
        );

        if (hasStorageMounts && Directory(storageRoot).existsSync()) {
          initialAndroidRoot = storageRoot;
        } else {
          // Otherwise prefer the primary volume if present; fall back to the first discovered root.
          initialAndroidRoot = roots.firstWhere(
            (r) => r.contains('/storage/emulated/0'),
            orElse: () => roots.first,
          );
        }

        await loadFolder(initialAndroidRoot!);
      } else if (_androidSongs.isNotEmpty) {
        initialAndroidRoot = '/storage/emulated/0';
        await loadFolder(initialAndroidRoot!);
      }
    } catch (e) {
      debugPrint('Failed to load Android root: $e');
    }
  }

  Future<List<String>> _defaultAndroidRootsLoader() async {
    try {
      final Set<String> roots = <String>{};

      // 1) App/API-reported external storage dirs (often primary)
      try {
        final paths = await ExternalPath.getExternalStorageDirectories();
        if (paths != null) {
          roots.addAll(paths.where((p) => p.isNotEmpty));
        }
      } catch (_) {
        // ignore
      }

      // 2) Heuristic: enumerate /storage mount points including USB volumes
      try {
        final storageDir = Directory('/storage');
        if (await storageDir.exists()) {
          final entries = storageDir.listSync(followLinks: false);
          for (final entity in entries) {
            if (entity is Directory) {
              final name = entity.uri.pathSegments.isNotEmpty
                  ? entity.uri.pathSegments.last
                  : entity.path.split('/').last;
              // Handle emulated -> emulated/0
              if (name == 'emulated') {
                final emu0 = Directory('/storage/emulated/0');
                if (emu0.existsSync()) {
                  roots.add(emu0.path);
                }
                continue;
              }
              // Include other mount points (e.g., XXXX-XXXX, sdcard1)
              roots.add(entity.path);
            }
          }
        }
      } catch (_) {
        // ignore
      }

      // 3) Fallback to common primary path if nothing found
      if (roots.isEmpty) {
        final fallback = Directory('/storage/emulated/0');
        if (fallback.existsSync()) {
          roots.add(fallback.path);
        }
      }

      // Return deterministic order for UI
      final list = roots.toList();
      list.sort();
      return list;
    } catch (_) {
      return [];
    }
  }

  void _clearListing() {
    currentPath = null;
    folders = [];
    tracks = [];
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
