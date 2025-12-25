import 'dart:io';

import 'package:external_path/external_path.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/audio_track.dart';
import '../services/library_browser.dart';
import '../services/library_service.dart';

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.libraryBrowser,
    required this.libraryService,
    OnAudioQuery? audioQuery,
    Future<List<LibrarySong>> Function()? androidSongLoader,
    Future<List<String>> Function()? androidRootsLoader,
  })  : _audioQuery = audioQuery ?? OnAudioQuery(),
        _androidSongLoader = androidSongLoader,
        _androidRootsLoader = androidRootsLoader;

  final LibraryBrowser libraryBrowser;
  final LibraryService libraryService;
  final OnAudioQuery _audioQuery;
  final Future<List<LibrarySong>> Function()? _androidSongLoader;
  final Future<List<String>> Function()? _androidRootsLoader;

  bool isLoading = false;
  String? error;
  String? currentPath;
  bool hasPermission = !Platform.isAndroid;
  String? initialAndroidRoot;

  List<LibraryFolder> folders = [];
  List<AudioTrack> tracks = [];
  List<LibrarySong> _androidSongs = [];

  Future<void> init() async {
    if (Platform.isAndroid) {
      await _checkAndroidPermission();
      if (hasPermission) {
        await _ensureAndroidSongsLoaded();
        await loadRoot();
      }
    }
  }

  Future<void> _checkAndroidPermission() async {
    try {
      final storageStatus = await Permission.storage.status;
      final audioStatus = await Permission.audio.status;
      final micStatus = await Permission.microphone.status;
      hasPermission = (storageStatus.isGranted || audioStatus.isGranted) && micStatus.isGranted;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to check permissions: $e');
      hasPermission = false;
      notifyListeners();
    }
  }

  Future<void> requestPermission() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final statuses = await [
        Permission.storage,
        Permission.audio,
        Permission.microphone,
      ].request();

      hasPermission =
          (statuses[Permission.storage]!.isGranted || statuses[Permission.audio]!.isGranted) &&
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
      notifyListeners();
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
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        await _ensureAndroidSongsLoaded();
        final listing = libraryBrowser.buildVirtualListing(
          basePath: path,
          songs: _androidSongs,
        );
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
      notifyListeners();
    }
  }

  Future<void> navigateUp() async {
    if (currentPath == null) return;

    if (Platform.isAndroid && initialAndroidRoot != null && currentPath == initialAndroidRoot) {
      _clearListing();
      notifyListeners();
      return;
    }

    if (libraryService.rootsNotifier.value.containsKey(currentPath)) {
      _clearListing();
      notifyListeners();
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
      final filtered = _androidSongs
          .where((song) => song.path.startsWith(currentPath!))
          .map((song) => AudioTrack(path: song.path, title: song.title))
          .toList();
      filtered.sort((a, b) => a.title.compareTo(b.title));
      return filtered;
    }

    // For macOS we rely on the file system; use the current listing or let caller recurse.
    return tracks;
  }

  Future<void> _ensureAndroidSongsLoaded() async {
    if (_androidSongs.isNotEmpty) return;
    final loader = _androidSongLoader ?? _defaultAndroidSongLoader;
    _androidSongs = await loader();
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
        initialAndroidRoot = roots.first;
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
      final paths = await ExternalPath.getExternalStorageDirectories();
      return paths ?? <String>[];
    } catch (_) {
      return [];
    }
  }

  void _clearListing() {
    currentPath = null;
    folders = [];
    tracks = [];
  }
}
