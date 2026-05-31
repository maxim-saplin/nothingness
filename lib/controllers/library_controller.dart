import 'dart:io';

import 'package:external_path/external_path.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/audio_track.dart';
import '../services/android_smart_roots.dart';
import '../services/library_browser.dart';
import '../services/library_service.dart';
import '../services/media_store_freshness.dart';
import '../models/supported_extensions.dart';
import '../services/metadata_extractor.dart';
import '../services/platform_channels.dart';

final _log = Logger('nothingness.library');

// Static function for isolate execution.
Future<List<LibrarySong>> _loadAndroidSongsInIsolate(
  RootIsolateToken rootToken,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  final songs = await OnAudioQuery().querySongs(
    sortType: null,
    orderType: OrderType.ASC_OR_SMALLER,
    uriType: UriType.EXTERNAL,
    ignoreCase: true,
  );
  return songs
      .map((s) => LibrarySong(
            path: s.data,
            title: SupportedExtensions.stripFromTitle(s.title),
          ))
      .toList();
}

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.libraryBrowser,
    required this.libraryService,
    MediaStoreFreshness? mediaStoreFreshness,
    bool? isAndroidOverride,
    OnAudioQuery? audioQuery,
    Future<List<LibrarySong>> Function()? androidSongLoader,
    Future<List<String>> Function()? androidRootsLoader,
    Future<bool> Function(String path)? androidFolderRescan,
    Future<void> Function(Duration duration)? waitForFolderRescan,
    List<Duration>? folderRescanReloadDelays,
  })  : _audioQuery = audioQuery ?? OnAudioQuery(),
        _mediaStoreFreshness = mediaStoreFreshness ??
            (Platform.isAndroid
                ? AndroidMediaStoreFreshness()
                : NoopMediaStoreFreshness()),
        _isAndroidOverride = isAndroidOverride,
        _androidSongLoader = androidSongLoader,
        _androidRootsLoader = androidRootsLoader,
        _androidFolderRescan =
            androidFolderRescan ?? PlatformChannels().rescanFolder,
        _waitForFolderRescan =
            waitForFolderRescan ?? Future<void>.delayed,
        _folderRescanReloadDelays = folderRescanReloadDelays ??
            const [
              Duration(milliseconds: 250),
              Duration(milliseconds: 500),
              Duration(milliseconds: 900),
            ];

  final LibraryBrowser libraryBrowser;
  final LibraryService libraryService;
  final OnAudioQuery _audioQuery;
  final MediaStoreFreshness _mediaStoreFreshness;
  final bool? _isAndroidOverride;
  final Future<List<LibrarySong>> Function()? _androidSongLoader;
  final Future<List<String>> Function()? _androidRootsLoader;
  final Future<bool> Function(String path) _androidFolderRescan;
  final Future<void> Function(Duration duration) _waitForFolderRescan;
  final List<Duration> _folderRescanReloadDelays;

  bool isLoading = false;
  bool isScanning = false;
  String? error;
  String? currentPath;
  bool hasPermission = !Platform.isAndroid;
  String? initialAndroidRoot;

  /// Android-only: computed smart root sections (grouped by device/mount).
  /// When `currentPath == null`, the UI can render these as the entry list.
  List<SmartRootSection> androidSmartRootSections = const [];

  List<LibraryFolder> folders = [];
  List<AudioTrack> tracks = [];
  List<LibrarySong> _androidSongs = [];
  bool _disposed = false;

  bool get isAndroid => _isAndroidOverride ?? Platform.isAndroid;

  /// OWN-mode library gate permissions (B-017): audio only — mic is a
  /// separately-requested BACKGROUND-mode dependency, kept out so denying it
  /// doesn't block the library.
  @visibleForTesting
  static const List<Permission> ownModePermissionList = [Permission.audio];

  /// OWN-mode `hasPermission` from a `permission_handler` status map (B-017):
  /// gated on audio only.
  @visibleForTesting
  static bool computeOwnModeHasPermission(
    Map<Permission, PermissionStatus> statuses,
  ) =>
      statuses[Permission.audio]?.isGranted ?? false;

  /// All MediaStore songs cached this session (Android only; empty elsewhere or
  /// before [_ensureAndroidSongsLoaded]). Used by Void search (B-009) to cover
  /// the whole library, not just the loaded folder.
  List<LibrarySong> get androidSongs => List.unmodifiable(_androidSongs);

  Future<void> init() async {
    if (!isAndroid) return;
    await _checkAndroidPermission();
    if (!hasPermission) return;
    // Force rescan when MediaStore is newer than last scan.
    if (await _shouldRefreshLibrary()) _androidSongs = [];
    await _ensureAndroidSongsLoaded();
    await loadRoot();
  }

  /// On "Folders" tab navigation (Android-only): refresh if MediaStore changed,
  /// else no-op.
  Future<void> onFoldersTabVisible() async {
    if (!isAndroid || !hasPermission || isScanning) return;
    try {
      if (await _mediaStoreFreshness.consumeIfChanged()) await refreshLibrary();
    } catch (e) {
      debugPrint('Error checking MediaStore freshness: $e');
    }
  }

  /// All MediaStore songs via [_audioQuery], sorted ascending by the external
  /// store. [ignoreCase] is passed through verbatim (null → package default).
  Future<List<SongModel>> _querySongs({bool? ignoreCase}) => _audioQuery
      .querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: ignoreCase,
      );

  /// Newest MediaStore timestamp, or null if no songs / no timestamps.
  Future<int?> _queryMaxSongTimestamp() async {
    int? max;
    for (final s in await _querySongs()) {
      final t = (s.dateAdded ?? 0) > (s.dateModified ?? 0)
          ? s.dateAdded
          : s.dateModified;
      if (t != null && (max == null || t > max)) max = t;
    }
    return max;
  }

  /// True if MediaStore has newer content than the cached scan timestamp.
  Future<bool> _shouldRefreshLibrary() async {
    try {
      final max = await _queryMaxSongTimestamp();
      if (max == null) return false;
      final last = libraryService.getLastScanTimestamp();
      if (last == null || max > last) {
        await libraryService.setLastScanTimestamp(max);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking library timestamp: $e');
      return false; // On error, use cached data.
    }
  }

  Future<void> _checkAndroidPermission() async {
    try {
      final statuses = {
        for (final perm in ownModePermissionList) perm: await perm.status,
      };
      hasPermission = computeOwnModeHasPermission(statuses);
    } catch (e) {
      debugPrint('Failed to check permissions: $e');
      hasPermission = false;
    }
    _safeNotifyListeners();
  }

  Future<void> requestPermission() async {
    isLoading = true;
    error = null;
    _safeNotifyListeners();
    try {
      // B-017: OWN-mode gate requests audio only (see ownModePermissionList).
      hasPermission =
          computeOwnModeHasPermission(await ownModePermissionList.request());
      if (hasPermission) {
        await _ensureAndroidSongsLoaded();
        await loadRoot();
      } else {
        error = 'Audio permission is required to browse your library';
      }
    } catch (e) {
      error = 'Failed to request permission: $e';
    } finally {
      isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> loadRoot() async {
    if (isAndroid) await _loadAndroidRoot();
  }

  Future<void> loadFolder(String path) async {
    isLoading = true;
    error = null;
    _safeNotifyListeners();
    try {
      final LibraryListing listing;
      if (isAndroid) {
        await _ensureAndroidSongsLoaded();
        // No filesystem fallback on Android — surface only MediaStore content
        // so it stays a music player; an empty path renders empty rather than
        // dumping into Alarms / Android / Notifications.
        listing = await libraryBrowser.buildVirtualListing(
          basePath: path,
          songs: _androidSongs,
        );
      } else {
        listing = await libraryBrowser.listFileSystem(path);
      }
      currentPath = listing.path;
      folders = listing.folders;
      tracks = listing.tracks;
    } catch (e) {
      error = '$e';
    } finally {
      isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> navigateUp() async {
    final path = currentPath;
    if (path == null) return;

    // At a smart-root entry or a persisted root, go back to the roots list.
    final atSmartRoot = isAndroid &&
        androidSmartRootSections.expand((s) => s.entries).contains(path);
    if (atSmartRoot || libraryService.rootsNotifier.value.containsKey(path)) {
      _clearListingAndNotify();
      return;
    }
    final parent = Directory(path).parent.path;
    if (parent != path) await loadFolder(parent);
  }

  Future<List<AudioTrack>> tracksForCurrentPath() async {
    final path = currentPath;
    if (path == null) return [];

    // macOS relies on the file system; reuse the current listing.
    if (!isAndroid) return tracks;

    await _ensureAndroidSongsLoaded();

    // Reuse the current listing if it already has tracks.
    if (tracks.isNotEmpty) {
      return [...tracks]..sort((a, b) => a.title.compareTo(b.title));
    }

    final extractor = createMetadataExtractor();
    final filtered = <AudioTrack>[];
    for (final song in _androidSongs.where((s) => s.path.startsWith(path))) {
      try {
        final t = await extractor.extractMetadata(song.path);
        // Use the on-disk filename as the title, not the ID3 tag.
        filtered.add(AudioTrack(
          path: t.path,
          title: p.basenameWithoutExtension(t.path),
          artist: t.artist,
          isNotFound: t.isNotFound,
        ));
      } catch (_) {
        filtered.add(AudioTrack(
          path: song.path,
          title: p.basenameWithoutExtension(song.path),
        ));
      }
    }
    return filtered..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<void> refreshLibrary() => runRefreshLibraryFlow();

  Future<void> repairCurrentFolderListing() async {
    final path = currentPath;
    if (!isAndroid || !hasPermission || path == null || isScanning) return;

    isScanning = true;
    error = null;
    _safeNotifyListeners();
    try {
      final initial = _currentListingSignature(path);
      if (!await _androidFolderRescan(path)) {
        _log.severe('Folder rescan request failed for $path');
        error = 'Could not repair this folder listing. Try again in a moment.';
        return;
      }

      var latest = initial;
      for (final delay in _folderRescanReloadDelays) {
        await _waitForFolderRescan(delay);
        await runRefreshLibraryFlow(
          manageScanningState: false,
          pathToReload: path,
        );
        final refreshed = _currentListingSignature(path);
        if (refreshed != initial || refreshed != latest) break;
        latest = refreshed;
      }
    } catch (e) {
      _log.severe('Failed to repair folder listing for $path: $e');
      error = 'Failed to repair this folder listing: $e';
    } finally {
      isScanning = false;
      _safeNotifyListeners();
    }
  }

  @visibleForTesting
  Future<void> runRefreshLibraryFlow({
    bool manageScanningState = true,
    String? pathToReload,
  }) async {
    if (!isAndroid || !hasPermission) return;

    if (manageScanningState) {
      isScanning = true;
      error = null;
      _safeNotifyListeners();
    }
    try {
      _androidSongs = [];
      await _ensureAndroidSongsLoaded();
      final reloadPath = pathToReload ?? currentPath;
      await (reloadPath != null ? loadFolder(reloadPath) : loadRoot());
    } catch (e) {
      error = 'Failed to refresh library: $e';
    } finally {
      if (manageScanningState) {
        isScanning = false;
        _safeNotifyListeners();
      }
    }
  }

  Future<void> _ensureAndroidSongsLoaded() async {
    if (_androidSongs.isNotEmpty) return;
    isScanning = true;
    _safeNotifyListeners();
    try {
      // Run in isolate to avoid blocking the UI thread.
      _androidSongs = await compute(
        _loadAndroidSongsInIsolate,
        RootIsolateToken.instance!,
      );
      if (_androidSongs.isNotEmpty) {
        try {
          final max = await _queryMaxSongTimestamp();
          if (max != null) await libraryService.setLastScanTimestamp(max);
        } catch (e) {
          debugPrint('Error updating scan timestamp: $e');
        }
      }
    } catch (e) {
      debugPrint(
        'Error loading songs in isolate, falling back to main thread: $e',
      );
      try {
        _androidSongs = await (_androidSongLoader ?? _defaultAndroidSongLoader)();
      } catch (e2) {
        debugPrint('Error loading songs: $e2');
        error = 'Failed to load songs: $e2';
      }
    } finally {
      isScanning = false;
      _safeNotifyListeners();
    }
  }

  Future<List<LibrarySong>> _defaultAndroidSongLoader() async =>
      (await _querySongs(ignoreCase: true))
          .map((s) => LibrarySong(path: s.data, title: s.title))
          .toList();

  Future<void> _loadAndroidRoot() async {
    try {
      final roots = await (_androidRootsLoader ?? _defaultAndroidRootsLoader)();
      if (roots.isNotEmpty && _androidSongs.isNotEmpty) {
        // Smart roots (closest music folders) per device/mount.
        androidSmartRootSections = AndroidSmartRoots.compute(
          deviceRoots: roots,
          songs: _androidSongs,
          maxEntriesPerDevice: 5,
        );
        final smartEntries =
            androidSmartRootSections.expand((s) => s.entries).toList()..sort();

        // B-001: with no music-bearing smart roots, leave the listing empty
        // ("no music found") rather than falling through to the device-root
        // filesystem (the unwanted Alarms / Android / Notifications view).
        if (smartEntries.length == 1) {
          // Zero-click: open the sole entry immediately.
          initialAndroidRoot = smartEntries.single;
          await loadFolder(initialAndroidRoot!);
          return;
        }
        // Empty → no-music state; multiple → smart-roots list.
      }
      // No songs/roots → empty smart-roots view (no filesystem listing).
      _clearListingAndNotify();
    } catch (e) {
      debugPrint('Failed to load Android root: $e');
    }
  }

  Future<List<String>> _defaultAndroidRootsLoader() async {
    try {
      final roots = <String>{};

      // 1) App/API-reported external storage dirs (often primary).
      try {
        final paths = await ExternalPath.getExternalStorageDirectories();
        if (paths != null) roots.addAll(paths.where((p) => p.isNotEmpty));
      } catch (_) {}

      // 2) Enumerate /storage mount points including USB volumes.
      try {
        final storageDir = Directory('/storage');
        if (await storageDir.exists()) {
          for (final entity in storageDir.listSync(followLinks: false)) {
            if (entity is! Directory) continue;
            final name = entity.uri.pathSegments.isNotEmpty
                ? entity.uri.pathSegments.last
                : entity.path.split('/').last;
            if (name == 'emulated') {
              // Map emulated -> emulated/0.
              final emu0 = Directory('/storage/emulated/0');
              if (emu0.existsSync()) roots.add(emu0.path);
            } else {
              roots.add(entity.path); // e.g. XXXX-XXXX, sdcard1
            }
          }
        }
      } catch (_) {}

      // 3) Fallback to common primary path if nothing found.
      if (roots.isEmpty) {
        final fallback = Directory('/storage/emulated/0');
        if (fallback.existsSync()) roots.add(fallback.path);
      }
      return roots.toList()..sort();
    } catch (_) {
      return [];
    }
  }

  void _clearListingAndNotify() {
    currentPath = null;
    folders = [];
    tracks = [];
    _safeNotifyListeners();
  }

  String _currentListingSignature(String expectedPath) {
    if (currentPath != expectedPath) return 'path=${currentPath ?? ''}';
    String sorted(Iterable<String> paths) => (paths.toList()..sort()).join(',');
    return '$expectedPath|folders=${sorted(folders.map((f) => f.path))}'
        '|tracks=${sorted(tracks.map((t) => t.path))}';
  }

  void _safeNotifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
