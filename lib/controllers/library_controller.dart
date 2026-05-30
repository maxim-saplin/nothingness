import 'dart:io';

import 'package:external_path/external_path.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/audio_track.dart';
import '../models/log_entry.dart';
import '../services/android_smart_roots.dart';
import '../services/library_browser.dart';
import '../services/library_service.dart';
import '../services/logging_service.dart';
import '../services/media_store_freshness.dart';
import '../models/supported_extensions.dart';
import '../services/metadata_extractor.dart';
import '../services/platform_channels.dart';

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
      .map((song) => LibrarySong(
            path: song.data,
            title: SupportedExtensions.stripFromTitle(song.title),
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
  }) : _audioQuery = audioQuery ?? OnAudioQuery(),
       _mediaStoreFreshness =
           mediaStoreFreshness ??
           (Platform.isAndroid
               ? AndroidMediaStoreFreshness()
               : NoopMediaStoreFreshness()),
       _isAndroidOverride = isAndroidOverride,
       _androidSongLoader = androidSongLoader,
       _androidRootsLoader = androidRootsLoader,
       _androidFolderRescan =
           androidFolderRescan ?? PlatformChannels().rescanFolder,
       _waitForFolderRescan =
           waitForFolderRescan ??
           ((duration) => Future<void>.delayed(duration)),
       _folderRescanReloadDelays =
           folderRescanReloadDelays ??
           const <Duration>[
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

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;
  bool get isAndroid => _isAndroid;

  /// OWN-mode library gate permissions (B-017): audio only — mic is a
  /// separately-requested BACKGROUND-mode dependency, kept out so denying it
  /// doesn't block the library.
  @visibleForTesting
  static const List<Permission> ownModePermissionList = <Permission>[
    Permission.audio,
  ];

  /// OWN-mode `hasPermission` from a `permission_handler` status map (B-017):
  /// gated on audio only.
  @visibleForTesting
  static bool computeOwnModeHasPermission(
    Map<Permission, PermissionStatus> statuses,
  ) {
    return statuses[Permission.audio]?.isGranted ?? false;
  }

  /// All MediaStore songs cached this session (Android only; empty elsewhere or
  /// before [_ensureAndroidSongsLoaded]). Used by Void search (B-009) to cover
  /// the whole library, not just the loaded folder.
  List<LibrarySong> get androidSongs => List.unmodifiable(_androidSongs);

  Future<void> init() async {
    if (!_isAndroid) return;
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
    if (!_isAndroid) return;
    if (!hasPermission) return;
    if (isScanning) return;

    try {
      final changed = await _mediaStoreFreshness.consumeIfChanged();
      if (changed) {
        await refreshLibrary();
      }
    } catch (e) {
      debugPrint('Error checking MediaStore freshness: $e');
    }
  }

  /// Max of dateAdded/dateModified across [songs], or null if none present.
  int? _getMaxSongTimestamp(List<SongModel> songs) {
    int? maxTimestamp;
    for (final song in songs) {
      final timestamp = (song.dateAdded ?? 0) > (song.dateModified ?? 0)
          ? song.dateAdded
          : song.dateModified;
      if (timestamp != null &&
          (maxTimestamp == null || timestamp > maxTimestamp)) {
        maxTimestamp = timestamp;
      }
    }
    return maxTimestamp;
  }

  /// All MediaStore songs via [_audioQuery], sorted ascending by the external
  /// store. [ignoreCase] is passed through verbatim (null → package default).
  Future<List<SongModel>> _querySongs({bool? ignoreCase}) {
    return _audioQuery.querySongs(
      sortType: null,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: ignoreCase,
    );
  }

  /// Newest MediaStore timestamp, or null if no songs / no timestamps.
  Future<int?> _queryMaxSongTimestamp() async {
    final sampleSongs = await _querySongs();
    return sampleSongs.isEmpty ? null : _getMaxSongTimestamp(sampleSongs);
  }

  /// True if MediaStore has newer content than the cached scan timestamp.
  Future<bool> _shouldRefreshLibrary() async {
    try {
      final maxTimestamp = await _queryMaxSongTimestamp();
      if (maxTimestamp == null) return false;

      final lastScanTimestamp = libraryService.getLastScanTimestamp();
      if (lastScanTimestamp == null || maxTimestamp > lastScanTimestamp) {
        await libraryService.setLastScanTimestamp(maxTimestamp);
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
      final statuses = <Permission, PermissionStatus>{
        for (final p in ownModePermissionList) p: await p.status,
      };
      hasPermission = computeOwnModeHasPermission(statuses);
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
      // B-017: OWN-mode gate requests audio only (see ownModePermissionList).
      final statuses = await ownModePermissionList.request();
      hasPermission = computeOwnModeHasPermission(statuses);

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
    if (_isAndroid) {
      await _loadAndroidRoot();
    }
  }

  Future<void> loadFolder(String path) async {
    isLoading = true;
    error = null;
    _safeNotifyListeners();

    try {
      final LibraryListing listing;
      if (_isAndroid) {
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
    if (currentPath == null) return;

    // At a smart-root entry or a persisted root, go back to the roots list.
    final atSmartRoot = _isAndroid &&
        androidSmartRootSections
            .expand((s) => s.entries)
            .contains(currentPath);
    if (atSmartRoot ||
        libraryService.rootsNotifier.value.containsKey(currentPath)) {
      _clearListingAndNotify();
      return;
    }

    final parent = Directory(currentPath!).parent.path;
    if (parent == currentPath) return;
    await loadFolder(parent);
  }

  Future<List<AudioTrack>> tracksForCurrentPath() async {
    if (currentPath == null) return [];

    if (_isAndroid) {
      await _ensureAndroidSongsLoaded();

      // Reuse the current listing if it already has tracks.
      if (tracks.isNotEmpty && currentPath != null) {
        return List<AudioTrack>.from(tracks)
          ..sort((a, b) => a.title.compareTo(b.title));
      }

      final extractor = createMetadataExtractor();
      final filtered = <AudioTrack>[];
      for (final song
          in _androidSongs.where((s) => s.path.startsWith(currentPath!))) {
        try {
          final track = await extractor.extractMetadata(song.path);
          // Use the on-disk filename as the title, not the ID3 tag.
          filtered.add(AudioTrack(
            path: track.path,
            title: p.basenameWithoutExtension(track.path),
            artist: track.artist,
            isNotFound: track.isNotFound,
          ));
        } catch (e) {
          filtered.add(AudioTrack(
            path: song.path,
            title: p.basenameWithoutExtension(song.path),
          ));
        }
      }
      filtered.sort((a, b) => a.title.compareTo(b.title));
      return filtered;
    }

    // macOS relies on the file system; reuse the current listing.
    return tracks;
  }

  Future<void> refreshLibrary() async {
    await runRefreshLibraryFlow();
  }

  Future<void> repairCurrentFolderListing() async {
    if (!_isAndroid || !hasPermission) return;

    final path = currentPath;
    if (path == null || isScanning) return;

    isScanning = true;
    error = null;
    _safeNotifyListeners();

    try {
      final initialSignature = _currentListingSignature(path);
      final started = await _androidFolderRescan(path);
      if (!started) {
        LoggingService().log(
          tag: 'Library',
          message: 'Folder rescan request failed for $path',
          level: LogLevel.error,
        );
        error = 'Could not repair this folder listing. Try again in a moment.';
        return;
      }

      var latestSignature = initialSignature;
      for (final delay in _folderRescanReloadDelays) {
        await _waitForFolderRescan(delay);
        await runRefreshLibraryFlow(
          manageScanningState: false,
          pathToReload: path,
        );

        final refreshedSignature = _currentListingSignature(path);
        if (refreshedSignature != initialSignature ||
            refreshedSignature != latestSignature) {
          break;
        }
        latestSignature = refreshedSignature;
      }
    } catch (e) {
      LoggingService().log(
        tag: 'Library',
        message: 'Failed to repair folder listing for $path: $e',
        level: LogLevel.error,
      );
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
    await _refreshLibraryImpl(
      manageScanningState: manageScanningState,
      pathToReload: pathToReload,
    );
  }

  Future<void> _refreshLibraryImpl({
    required bool manageScanningState,
    String? pathToReload,
  }) async {
    if (!_isAndroid || !hasPermission) return;

    if (manageScanningState) {
      isScanning = true;
      error = null;
      _safeNotifyListeners();
    }

    try {
      _androidSongs = [];
      await _ensureAndroidSongsLoaded();

      final reloadPath = pathToReload ?? currentPath;
      if (reloadPath != null) {
        await loadFolder(reloadPath);
      } else {
        await loadRoot();
      }
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
          final maxTimestamp = await _queryMaxSongTimestamp();
          if (maxTimestamp != null) {
            await libraryService.setLastScanTimestamp(maxTimestamp);
          }
        } catch (e) {
          debugPrint('Error updating scan timestamp: $e');
        }
      }
    } catch (e) {
      debugPrint(
        'Error loading songs in isolate, falling back to main thread: $e',
      );
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
    final songs = await _querySongs(ignoreCase: true);
    return songs
        .map((song) => LibrarySong(path: song.data, title: song.title))
        .toList();
  }

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
        _clearListingAndNotify();
        return;
      }

      // No songs/roots → empty smart-roots view (no filesystem listing).
      _clearListingAndNotify();
    } catch (e) {
      debugPrint('Failed to load Android root: $e');
    }
  }

  Future<List<String>> _defaultAndroidRootsLoader() async {
    try {
      final Set<String> roots = <String>{};

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
              continue;
            }
            roots.add(entity.path); // e.g. XXXX-XXXX, sdcard1
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

  void _clearListing() {
    currentPath = null;
    folders = [];
    tracks = [];
  }

  void _clearListingAndNotify() {
    _clearListing();
    _safeNotifyListeners();
  }

  String _currentListingSignature(String expectedPath) {
    if (currentPath != expectedPath) {
      return 'path=${currentPath ?? ''}';
    }

    String sortedPaths(Iterable<String> paths) =>
        (paths.toList()..sort()).join(',');
    final folderPaths = sortedPaths(folders.map((folder) => folder.path));
    final trackPaths = sortedPaths(tracks.map((track) => track.path));
    return '$expectedPath|folders=$folderPaths|tracks=$trackPaths';
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
