import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/audio_track.dart';
import '../models/supported_extensions.dart';
import '../models/webdav_source.dart';
import 'library_browser.dart';
import 'metadata_extractor.dart';
import 'track_file_resolver.dart';
import 'webdav_client.dart';
import 'webdav_track_path.dart';

abstract interface class WebDavSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureWebDavSecretStore implements WebDavSecretStore {
  SecureWebDavSecretStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Persists WebDAV source metadata and directory snapshots, and keeps a bounded
/// on-disk cache for the current and preloaded audio tracks.
class WebDavLibraryService extends ChangeNotifier implements TrackFileResolver {
  WebDavLibraryService({
    HiveInterface? hive,
    WebDavSecretStore? secretStore,
    http.Client? httpClient,
    Future<Directory> Function()? cacheDirectory,
    Random? random,
  }) : _hive = hive ?? Hive,
       _secretStore = secretStore ?? SecureWebDavSecretStore(),
       _httpClient = httpClient ?? http.Client(),
       _cacheDirectoryProvider =
           cacheDirectory ?? getApplicationSupportDirectory,
       _random = random ?? Random();

  static final WebDavLibraryService instance = WebDavLibraryService();

  static const _sourceBoxName = 'webDavSources';
  static const _indexBoxName = 'webDavIndex';
  static const _cacheBoxName = 'webDavAudioCache';
  static const _metaBoxName = 'webDavMeta';
  static const _cacheLimitKey = 'cacheLimitBytes';
  static const _preloadCountKey = 'preloadCount';
  static const defaultCacheLimitBytes = 512 * 1024 * 1024;
  static const defaultPreloadCount = 3;
  static const _refreshInterval = Duration(minutes: 2);

  final HiveInterface _hive;
  final WebDavSecretStore _secretStore;
  final http.Client _httpClient;
  final Future<Directory> Function() _cacheDirectoryProvider;
  final Random _random;

  Box<dynamic>? _sourceBox;
  Box<dynamic>? _indexBox;
  Box<dynamic>? _cacheBox;
  Box<dynamic>? _metaBox;
  Directory? _cacheDirectory;
  bool _initialized = false;
  Future<void>? _initializing;

  final ValueNotifier<List<WebDavSource>> sourcesNotifier = ValueNotifier(
    const [],
  );
  final ValueNotifier<Map<String, WebDavSyncProgress>> syncProgressNotifier =
      ValueNotifier(const {});
  final ValueNotifier<Map<String, WebDavTransferProgress>>
  transferProgressNotifier = ValueNotifier(const {});
  final ValueNotifier<int> snapshotRevisionNotifier = ValueNotifier(0);
  final ValueNotifier<int> cacheRevisionNotifier = ValueNotifier(0);
  final ValueNotifier<int> preloadCountNotifier = ValueNotifier(
    defaultPreloadCount,
  );

  final Map<String, Future<void>> _syncs = {};
  final Map<String, Future<String>> _downloads = {};
  final Map<String, int> _pinCounts = {};

  List<WebDavSource> get sources => sourcesNotifier.value;

  int get cacheLimitBytes =>
      _metaBox?.get(_cacheLimitKey) as int? ?? defaultCacheLimitBytes;

  Future<void> init() async {
    if (_initialized) return;
    final pending = _initializing;
    if (pending != null) return pending;

    final completer = Completer<void>();
    _initializing = completer.future;
    try {
      _sourceBox ??= await _hive.openBox<dynamic>(_sourceBoxName);
      _indexBox ??= await _hive.openBox<dynamic>(_indexBoxName);
      _cacheBox ??= await _hive.openBox<dynamic>(_cacheBoxName);
      _metaBox ??= await _hive.openBox<dynamic>(_metaBoxName);
      final preloadCount = _metaBox!.get(_preloadCountKey);
      if (preloadCount is int) {
        preloadCountNotifier.value = preloadCount.clamp(1, 10);
      }
      _cacheDirectory = Directory(
        p.join(
          (await _cacheDirectoryProvider()).path,
          'nothingness_webdav_audio',
        ),
      );
      await _cacheDirectory!.create(recursive: true);
      await for (final entity in _cacheDirectory!.list()) {
        if (entity is File && p.basename(entity.path).contains('.part-')) {
          await entity.delete();
        }
      }
      sourcesNotifier.value = _sourceBox!.values
          .whereType<Map>()
          .map(WebDavSource.fromJson)
          .toList(growable: false);
      _initialized = true;
      completer.complete();
    } catch (error, stackTrace) {
      _initializing = null;
      completer.completeError(error, stackTrace);
      rethrow;
    }
  }

  static Uri accountRootUri({
    required String serverUrl,
    required String username,
  }) {
    final server = Uri.parse(serverUrl.trim());
    if (server.scheme != 'https' || server.host.isEmpty) {
      throw const FormatException('Use an HTTPS Nextcloud server URL.');
    }
    if (server.userInfo.isNotEmpty ||
        server.query.isNotEmpty ||
        server.fragment.isNotEmpty) {
      throw const FormatException(
        'Server URL must not contain credentials or a query.',
      );
    }
    final prefix = server.pathSegments.where((segment) => segment.isNotEmpty);
    return Uri(
      scheme: server.scheme,
      host: server.host,
      port: server.hasPort ? server.port : null,
      pathSegments: [...prefix, 'remote.php', 'dav', 'files', username],
    );
  }

  Future<WebDavSource> addSource({
    required String name,
    required String serverUrl,
    required String username,
    required String appPassword,
    required String folderPath,
  }) async {
    await init();
    final normalizedFolder = _normalizeFolderPath(folderPath);
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty) {
      throw const FormatException('Username is required.');
    }
    final rootUri = accountRootUri(
      serverUrl: serverUrl,
      username: normalizedUsername,
    );
    final folderSegments = normalizedFolder
        .split('/')
        .where((s) => s.isNotEmpty);
    final source = WebDavSource(
      id: _newId(),
      name: name.trim().isEmpty
          ? (folderSegments.isEmpty ? normalizedUsername : folderSegments.last)
          : name.trim(),
      serverUrl: Uri.parse(
        serverUrl.trim(),
      ).replace(path: _baseServerPath(serverUrl)).toString(),
      username: normalizedUsername,
      folderPath: normalizedFolder,
    );
    final client = WebDavClient(
      accountRoot: rootUri,
      username: source.username,
      password: appPassword,
      client: _httpClient,
    );
    await client.listDirectory(source.folderPath);
    await _secretStore.write(_passwordKey(source.id), appPassword);
    await _sourceBox!.put(source.id, source.toJson());
    _reloadSources();
    unawaited(
      refreshSource(source.id).catchError((Object error) {
        _setProgress(
          WebDavSyncProgress(
            sourceId: source.id,
            foldersScanned: 0,
            tracksIndexed: 0,
            isComplete: true,
            error: _safeError(error),
          ),
        );
      }),
    );
    return source;
  }

  Future<void> removeSource(String sourceId) async {
    await init();
    final source = sourceForId(sourceId);
    if (source == null) return;
    await _sourceBox!.delete(sourceId);
    await _secretStore.delete(_passwordKey(sourceId));
    await _deleteSourceSnapshot(sourceId);
    for (final key in _cacheBox!.keys.toList()) {
      final entry = _cacheBox!.get(key);
      if (entry is Map && entry['sourceId'] == sourceId) {
        final trackPath = entry['trackPath'] as String?;
        if (trackPath != null && (_pinCounts[trackPath] ?? 0) > 0) {
          await _cacheBox!.put(key, {...entry, 'stale': true});
        } else {
          await _deleteCacheRecord(key, entry);
        }
      }
    }
    _reloadSources();
    snapshotRevisionNotifier.value++;
    _refreshCacheRevision();
  }

  WebDavSource? sourceForId(String sourceId) {
    for (final source in sourcesNotifier.value) {
      if (source.id == sourceId) return source;
    }
    return null;
  }

  WebDavSource? sourceForTrackPath(String trackPath) {
    if (!WebDavTrackPath.isRemote(trackPath)) return null;
    return sourceForId(WebDavTrackPath.sourceId(trackPath));
  }

  String sourceRootPath(WebDavSource source) =>
      WebDavTrackPath.encode(source.id, source.folderPath);

  Future<LibraryListing> listFolder(String trackPath) async {
    await init();
    final sourceId = WebDavTrackPath.sourceId(trackPath);
    final relativePath = WebDavTrackPath.relativePath(trackPath);
    final record = _indexBox!.get(_indexKey(sourceId, relativePath));
    final entries = _entriesFromRecord(record);
    final folders = <LibraryFolder>[];
    final tracks = <AudioTrack>[];
    for (final entry in entries) {
      if (entry.isDirectory) {
        folders.add(
          LibraryFolder(
            path: WebDavTrackPath.encode(sourceId, entry.relativePath),
            name: entry.name,
          ),
        );
      } else if (_isSupported(entry.name)) {
        final id = WebDavTrackPath.encode(sourceId, entry.relativePath);
        tracks.add(buildTrackFromFilename(path: id, fileName: entry.name));
      }
    }
    folders.sort((a, b) => a.name.compareTo(b.name));
    tracks.sort((a, b) => a.title.compareTo(b.title));
    return LibraryListing(path: trackPath, folders: folders, tracks: tracks);
  }

  Future<List<AudioTrack>> tracksInTree(String trackPath) async {
    await init();
    final sourceId = WebDavTrackPath.sourceId(trackPath);
    final prefixPath = WebDavTrackPath.relativePath(trackPath);
    final keyPrefix = '$sourceId|';
    final tracks = <AudioTrack>[];
    for (final key in _indexBox!.keys.whereType<String>()) {
      if (!key.startsWith(keyPrefix)) continue;
      final directory = key.substring(keyPrefix.length);
      if (prefixPath.isNotEmpty &&
          directory != prefixPath &&
          !directory.startsWith('$prefixPath/')) {
        continue;
      }
      for (final entry in _entriesFromRecord(_indexBox!.get(key))) {
        if (!entry.isDirectory && _isSupported(entry.name)) {
          final id = WebDavTrackPath.encode(sourceId, entry.relativePath);
          tracks.add(buildTrackFromFilename(path: id, fileName: entry.name));
        }
      }
    }
    tracks.sort((a, b) => a.title.compareTo(b.title));
    return tracks;
  }

  Future<List<AudioTrack>> searchTracks(String query) async {
    await init();
    final lower = query.toLowerCase();
    if (lower.isEmpty) return const [];
    final tracks = <AudioTrack>[];
    for (final source in sourcesNotifier.value) {
      tracks.addAll(await tracksInTree(sourceRootPath(source)));
    }
    return tracks
        .where(
          (track) =>
              track.title.toLowerCase().contains(lower) ||
              track.artist.toLowerCase().contains(lower) ||
              WebDavTrackPath.basename(
                track.path,
              ).toLowerCase().contains(lower),
        )
        .toList(growable: false);
  }

  Future<void> refreshIfStale(String sourceId) async {
    final source = sourceForId(sourceId);
    if (source == null) return;
    final last = source.lastSyncedAtMs;
    if (last != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) <
            _refreshInterval) {
      return;
    }
    await refreshSource(sourceId);
  }

  Future<void> refreshSource(String sourceId) {
    final running = _syncs[sourceId];
    if (running != null) return running;
    final task = _refreshSource(sourceId);
    _syncs[sourceId] = task;
    return task.whenComplete(() {
      if (identical(_syncs[sourceId], task)) _syncs.remove(sourceId);
    });
  }

  Future<void> _refreshSource(String sourceId) async {
    await init();
    final source = sourceForId(sourceId);
    if (source == null) throw StateError('WebDAV source was removed.');
    _setProgress(
      WebDavSyncProgress(
        sourceId: sourceId,
        foldersScanned: 0,
        tracksIndexed: 0,
        isComplete: false,
      ),
    );
    var foldersScanned = 0;
    var tracksIndexed = 0;
    try {
      final client = await _clientFor(source);
      final rootKey = _indexKey(source.id, source.folderPath);
      final oldRoot = _indexBox!.get(rootKey);
      if (oldRoot == null) {
        final listing = await client.listDirectory(source.folderPath);
        await _storeDirectory(source, source.folderPath, listing);
        foldersScanned++;
        tracksIndexed += listing.entries
            .where((entry) => !entry.isDirectory && _isSupported(entry.name))
            .length;
        _publishProgress(sourceId, foldersScanned, tracksIndexed);
        await _refreshChildDirectories(source, client, listing.entries, (
          count,
          tracks,
        ) {
          foldersScanned += count;
          tracksIndexed += tracks;
          _publishProgress(sourceId, foldersScanned, tracksIndexed);
        });
      } else {
        final remoteEtag = await client.directoryEtag(source.folderPath);
        if (remoteEtag == null || remoteEtag != _etagFromRecord(oldRoot)) {
          await _syncChangedDirectory(
            source,
            client,
            source.folderPath,
            remoteEtag,
            (count, tracks) {
              foldersScanned += count;
              tracksIndexed += tracks;
              _publishProgress(sourceId, foldersScanned, tracksIndexed);
            },
          );
        } else {
          await _refreshChildDirectories(
            source,
            client,
            _entriesFromRecord(oldRoot),
            (count, tracks) {
              foldersScanned += count;
              tracksIndexed += tracks;
              _publishProgress(sourceId, foldersScanned, tracksIndexed);
            },
          );
        }
      }
      if (sourceForId(sourceId) == null) {
        await _deleteSourceSnapshot(sourceId);
        snapshotRevisionNotifier.value++;
        return;
      }
      await _sourceBox!.put(
        sourceId,
        source
            .copyWith(lastSyncedAtMs: DateTime.now().millisecondsSinceEpoch)
            .toJson(),
      );
      if (sourceForId(sourceId) == null) {
        await _sourceBox!.delete(sourceId);
        await _deleteSourceSnapshot(sourceId);
      }
      _reloadSources();
      _setProgress(
        WebDavSyncProgress(
          sourceId: sourceId,
          foldersScanned: foldersScanned,
          tracksIndexed: tracksIndexed,
          isComplete: true,
        ),
      );
      snapshotRevisionNotifier.value++;
    } catch (error) {
      snapshotRevisionNotifier.value++;
      _setProgress(
        WebDavSyncProgress(
          sourceId: sourceId,
          foldersScanned: foldersScanned,
          tracksIndexed: tracksIndexed,
          isComplete: true,
          error: _safeError(error),
        ),
      );
      rethrow;
    }
  }

  Future<void> _refreshChildDirectories(
    WebDavSource source,
    WebDavClient client,
    List<WebDavEntry> children,
    void Function(int folders, int tracks) onProgress,
  ) async {
    for (final entry in children.where((entry) => entry.isDirectory)) {
      final existing = _indexBox!.get(_indexKey(source.id, entry.relativePath));
      if (entry.etag != null &&
          existing != null &&
          entry.etag == _etagFromRecord(existing)) {
        await _refreshChildDirectories(
          source,
          client,
          _entriesFromRecord(existing),
          onProgress,
        );
        continue;
      }
      await _syncChangedDirectory(
        source,
        client,
        entry.relativePath,
        entry.etag,
        onProgress,
      );
    }
  }

  Future<void> _syncChangedDirectory(
    WebDavSource source,
    WebDavClient client,
    String relativePath,
    String? knownEtag,
    void Function(int folders, int tracks) onProgress,
  ) async {
    final key = _indexKey(source.id, relativePath);
    final oldRecord = _indexBox!.get(key);
    if (knownEtag != null &&
        oldRecord != null &&
        knownEtag == _etagFromRecord(oldRecord)) {
      return;
    }

    final listing = await client.listDirectory(relativePath);
    final oldEntries = _entriesFromRecord(oldRecord);
    final supportedEntries = listing.entries
        .where((entry) => entry.isDirectory || _isSupported(entry.name))
        .toList(growable: false);
    final newByName = {for (final entry in supportedEntries) entry.name: entry};
    for (final old in oldEntries) {
      final next = newByName[old.name];
      if (next == null || old.isDirectory != next.isDirectory) {
        await _removeIndexedPath(source.id, old.relativePath, old.isDirectory);
      } else if (!old.isDirectory && old.etag != next.etag) {
        await _invalidateTrack(
          WebDavTrackPath.encode(source.id, old.relativePath),
        );
      }
    }

    await _storeDirectory(
      source,
      relativePath,
      listing,
      entries: supportedEntries,
    );
    onProgress(
      1,
      supportedEntries
          .where((entry) => !entry.isDirectory && _isSupported(entry.name))
          .length,
    );
    await _refreshChildDirectories(
      source,
      client,
      supportedEntries,
      onProgress,
    );
  }

  Future<void> _storeDirectory(
    WebDavSource source,
    String relativePath,
    WebDavDirectoryListing listing, {
    List<WebDavEntry>? entries,
  }) async {
    final children =
        entries ??
        listing.entries
            .where((entry) => entry.isDirectory || _isSupported(entry.name))
            .toList(growable: false);
    await _indexBox!.put(_indexKey(source.id, relativePath), {
      'etag': listing.etag,
      'entries': children
          .map((entry) => entry.toJson())
          .toList(growable: false),
    });
  }

  Future<void> _deleteSourceSnapshot(String sourceId) async {
    final prefix = '$sourceId|';
    for (final key in _indexBox!.keys.whereType<String>().toList()) {
      if (key.startsWith(prefix)) await _indexBox!.delete(key);
    }
  }

  Future<void> _removeIndexedPath(
    String sourceId,
    String relativePath,
    bool isDirectory,
  ) async {
    if (isDirectory) {
      final record = _indexBox!.get(_indexKey(sourceId, relativePath));
      for (final child in _entriesFromRecord(record)) {
        await _removeIndexedPath(
          sourceId,
          child.relativePath,
          child.isDirectory,
        );
      }
      for (final key in _indexBox!.keys.whereType<String>().toList()) {
        if (key == _indexKey(sourceId, relativePath) ||
            key.startsWith('${_indexKey(sourceId, relativePath)}/')) {
          await _indexBox!.delete(key);
        }
      }
      return;
    }
    await _invalidateTrack(WebDavTrackPath.encode(sourceId, relativePath));
  }

  Future<LibraryListing> reloadCurrentPath(String trackPath) =>
      listFolder(trackPath);

  @override
  bool supports(String trackPath) => WebDavTrackPath.isRemote(trackPath);

  @override
  void pin(String trackPath) {
    if (!supports(trackPath)) return;
    _pinCounts.update(trackPath, (count) => count + 1, ifAbsent: () => 1);
  }

  @override
  void unpin(String trackPath) {
    if (!supports(trackPath)) return;
    final count = _pinCounts[trackPath] ?? 0;
    if (count <= 1) {
      _pinCounts.remove(trackPath);
      unawaited(_pruneCache().catchError((_) {}));
    } else {
      _pinCounts[trackPath] = count - 1;
    }
  }

  @override
  Future<String> resolveLocalPath(
    String trackPath, {
    bool preloading = false,
  }) async {
    await init();
    final sourceId = WebDavTrackPath.sourceId(trackPath);
    final relativePath = WebDavTrackPath.relativePath(trackPath);
    var entry = _findEntry(sourceId, relativePath);

    if (entry == null) {
      final source = sourceForId(sourceId);
      if (source != null) {
        await refreshSource(sourceId);
        entry = _findEntry(sourceId, relativePath);
      }
    }

    final cache = await _cachedFile(trackPath, entry?.etag);
    if (cache != null) return cache;

    final source = sourceForId(sourceId);
    if (source == null || entry == null) {
      throw StateError('No cached copy or WebDAV listing for this track.');
    }
    final downloadKey = _cacheKey(source.id, relativePath, entry.etag ?? '');
    final pending = _downloads[downloadKey];
    if (pending != null) return pending;
    final download = () async {
      final client = await _clientFor(source);
      return _downloadTrack(
        source,
        client,
        trackPath,
        entry!,
        preloading: preloading,
        retryStale: true,
      );
    }();
    _downloads[downloadKey] = download;
    try {
      return await download;
    } finally {
      if (identical(_downloads[downloadKey], download)) {
        _downloads.remove(downloadKey);
      }
    }
  }

  Future<String> _downloadTrack(
    WebDavSource source,
    WebDavClient client,
    String trackPath,
    WebDavEntry entry, {
    required bool preloading,
    required bool retryStale,
  }) async {
    final response = await client.openFile(
      entry.relativePath,
      etag: entry.etag,
    );
    final responseEtag = response.headers['etag'];
    if ((response.statusCode == 412 ||
            (entry.etag != null &&
                responseEtag != null &&
                entry.etag != responseEtag)) &&
        retryStale) {
      await response.stream.drain<void>();
      await refreshSource(source.id);
      final updated = _findEntry(source.id, entry.relativePath);
      if (updated != null) {
        return _downloadTrack(
          source,
          await _clientFor(source),
          trackPath,
          updated,
          preloading: preloading,
          retryStale: false,
        );
      }
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw WebDavException(
        'Could not download WebDAV audio',
        statusCode: response.statusCode,
      );
    }

    final etag = entry.etag ?? responseEtag ?? '';
    final cacheKey = _cacheKey(source.id, entry.relativePath, etag);
    final extension = p.extension(entry.name).toLowerCase();
    final target = File(p.join(_cacheDirectory!.path, '$cacheKey$extension'));
    final partial = File('${target.path}.part-${_random.nextInt(1 << 32)}');
    final total = response.contentLength ?? entry.size;
    _setTransfer(
      WebDavTransferProgress(
        trackPath: trackPath,
        bytesReceived: 0,
        totalBytes: total,
        isPreload: preloading,
      ),
    );
    var received = 0;
    IOSink? sink;
    try {
      sink = partial.openWrite();
      var lastUpdate = DateTime.now();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds >= 100) {
          _setTransfer(
            WebDavTransferProgress(
              trackPath: trackPath,
              bytesReceived: received,
              totalBytes: total,
              isPreload: preloading,
            ),
          );
          lastUpdate = now;
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (entry.size != null && received != entry.size) {
        throw StateError(
          'Incomplete WebDAV download ($received/${entry.size} bytes).',
        );
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      await _cacheBox!.put(cacheKey, {
        'sourceId': source.id,
        'trackPath': trackPath,
        'etag': etag,
        'filePath': target.path,
        'size': received,
        'lastUsedMs': DateTime.now().millisecondsSinceEpoch,
        'stale': false,
      });
      _setTransfer(null, key: trackPath);
      cacheRevisionNotifier.value++;
      await _pruneCache();
      return target.path;
    } catch (_) {
      await sink?.close();
      try {
        await partial.delete();
      } catch (_) {}
      _setTransfer(null, key: trackPath);
      rethrow;
    }
  }

  Future<String?> _cachedFile(String trackPath, String? etag) async {
    final matches = <MapEntry<dynamic, Map>>[];
    for (final key in _cacheBox!.keys) {
      final value = _cacheBox!.get(key);
      if (value is Map && value['trackPath'] == trackPath) {
        matches.add(MapEntry(key, value));
      }
    }
    matches.sort(
      (a, b) => (b.value['lastUsedMs'] as int? ?? 0).compareTo(
        a.value['lastUsedMs'] as int? ?? 0,
      ),
    );
    for (final candidate in matches) {
      if (etag != null && candidate.value['etag'] != etag) continue;
      final filePath = candidate.value['filePath'] as String?;
      if (filePath == null) continue;
      final file = File(filePath);
      if (!await file.exists()) {
        await _cacheBox!.delete(candidate.key);
        continue;
      }
      await _cacheBox!.put(candidate.key, {
        ...candidate.value,
        'lastUsedMs': DateTime.now().millisecondsSinceEpoch,
      });
      return file.path;
    }
    return null;
  }

  Future<void> _invalidateTrack(String trackPath) async {
    for (final key in _cacheBox!.keys.toList()) {
      final record = _cacheBox!.get(key);
      if (record is! Map || record['trackPath'] != trackPath) continue;
      if ((_pinCounts[trackPath] ?? 0) > 0) {
        await _cacheBox!.put(key, {...record, 'stale': true});
      } else {
        await _deleteCacheRecord(key, record);
      }
    }
    cacheRevisionNotifier.value++;
  }

  Future<void> _deleteCacheRecord(dynamic key, Map record) async {
    final filePath = record['filePath'] as String?;
    if (filePath != null) {
      try {
        await File(filePath).delete();
      } catch (_) {}
    }
    await _cacheBox!.delete(key);
  }

  Future<void> _pruneCache() async {
    final box = _cacheBox;
    if (box == null) return;
    final candidates = <MapEntry<dynamic, Map>>[];
    var total = 0;
    for (final key in box.keys.toList()) {
      final record = box.get(key);
      if (record is! Map) continue;
      final path = record['filePath'] as String?;
      final trackPath = record['trackPath'] as String?;
      if (path == null || trackPath == null || !await File(path).exists()) {
        await box.delete(key);
        continue;
      }
      final size = record['size'] as int? ?? 0;
      total += size;
      if ((_pinCounts[trackPath] ?? 0) == 0) {
        candidates.add(MapEntry(key, record));
      }
    }
    candidates.sort(
      (a, b) => (a.value['lastUsedMs'] as int? ?? 0).compareTo(
        b.value['lastUsedMs'] as int? ?? 0,
      ),
    );
    for (final candidate in candidates) {
      final stale = candidate.value['stale'] as bool? ?? false;
      if (!stale && total <= cacheLimitBytes) continue;
      total -= candidate.value['size'] as int? ?? 0;
      await _deleteCacheRecord(candidate.key, candidate.value);
    }
    cacheRevisionNotifier.value++;
  }

  Future<int> audioCacheSizeBytes({String? sourceId}) async {
    await init();
    var size = 0;
    for (final value in _cacheBox!.values) {
      if (value is! Map ||
          (sourceId != null && value['sourceId'] != sourceId)) {
        continue;
      }
      final filePath = value['filePath'] as String?;
      if (filePath != null && await File(filePath).exists()) {
        size += value['size'] as int? ?? 0;
      }
    }
    return size;
  }

  Future<int> snapshotSizeBytes({String? sourceId}) async {
    await init();
    final prefix = sourceId == null ? null : '$sourceId|';
    var bytes = 0;
    for (final key in _indexBox!.keys) {
      if (prefix != null && (key is! String || !key.startsWith(prefix))) {
        continue;
      }
      bytes += utf8.encode(jsonEncode(_indexBox!.get(key))).length;
    }
    return bytes;
  }

  Future<int> indexedTrackCount(String sourceId) async {
    final source = sourceForId(sourceId);
    return source == null
        ? 0
        : (await tracksInTree(sourceRootPath(source))).length;
  }

  Future<void> setCacheLimitMiB(int mebibytes) async {
    await init();
    final value = mebibytes.clamp(64, 4096) * 1024 * 1024;
    await _metaBox!.put(_cacheLimitKey, value);
    await _pruneCache();
  }

  Future<void> setPreloadCount(int count) async {
    RangeError.checkValueInInterval(count, 1, 10, 'count');
    await init();
    await _metaBox!.put(_preloadCountKey, count);
    preloadCountNotifier.value = count;
  }

  Future<void> clearUnusedAudioCache({String? sourceId}) async {
    await init();
    for (final key in _cacheBox!.keys.toList()) {
      final record = _cacheBox!.get(key);
      if (record is! Map) continue;
      if (sourceId != null && record['sourceId'] != sourceId) continue;
      final trackPath = record['trackPath'] as String?;
      if (trackPath != null && (_pinCounts[trackPath] ?? 0) > 0) continue;
      await _deleteCacheRecord(key, record);
    }
    cacheRevisionNotifier.value++;
  }

  Future<void> _refreshCacheRevision() async => cacheRevisionNotifier.value++;

  WebDavEntry? _findEntry(String sourceId, String relativePath) {
    final parent = p.posix.dirname(relativePath);
    final normalizedParent = parent == '.' ? '' : parent;
    final record = _indexBox?.get(_indexKey(sourceId, normalizedParent));
    for (final entry in _entriesFromRecord(record)) {
      if (entry.relativePath == relativePath) return entry;
    }
    return null;
  }

  List<WebDavEntry> _entriesFromRecord(dynamic record) {
    if (record is! Map || record['entries'] is! List) return const [];
    return (record['entries'] as List)
        .whereType<Map>()
        .map(WebDavEntry.fromJson)
        .toList(growable: false);
  }

  String? _etagFromRecord(dynamic record) =>
      record is Map ? record['etag'] as String? : null;

  Future<WebDavClient> _clientFor(WebDavSource source) async {
    final password = await _secretStore.read(_passwordKey(source.id));
    if (password == null || password.isEmpty) {
      throw StateError(
        'WebDAV app password is unavailable. Reconnect the source.',
      );
    }
    return WebDavClient(
      accountRoot: accountRootUri(
        serverUrl: source.serverUrl,
        username: source.username,
      ),
      username: source.username,
      password: password,
      client: _httpClient,
    );
  }

  String _indexKey(String sourceId, String relativePath) =>
      '$sourceId|$relativePath';

  String _passwordKey(String sourceId) => 'webdav.appPassword.$sourceId';

  String _cacheKey(String sourceId, String relativePath, String etag) => sha256
      .convert(utf8.encode('$sourceId\u0000$relativePath\u0000$etag'))
      .toString();

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 24).toRadixString(36)}';

  void _reloadSources() {
    final box = _sourceBox;
    if (box == null) return;
    sourcesNotifier.value = box.values
        .whereType<Map>()
        .map(WebDavSource.fromJson)
        .toList(growable: false);
  }

  void _setProgress(WebDavSyncProgress progress) {
    syncProgressNotifier.value = {
      ...syncProgressNotifier.value,
      progress.sourceId: progress,
    };
  }

  void _publishProgress(String sourceId, int folders, int tracks) =>
      _setProgress(
        WebDavSyncProgress(
          sourceId: sourceId,
          foldersScanned: folders,
          tracksIndexed: tracks,
          isComplete: false,
        ),
      );

  void _setTransfer(WebDavTransferProgress? progress, {String? key}) {
    final path = key ?? progress?.trackPath;
    if (path == null) return;
    final next = {...transferProgressNotifier.value};
    if (progress == null) {
      next.remove(path);
    } else {
      next[path] = progress;
    }
    transferProgressNotifier.value = next;
  }

  bool _isSupported(String name) => SupportedExtensions.supportedExtensions
      .contains(p.extension(name).replaceAll('.', '').toLowerCase());

  String _normalizeFolderPath(String path) {
    final segments = path
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.any((segment) => segment == '.' || segment == '..')) {
      throw const FormatException(
        'Folder path must stay inside the account root.',
      );
    }
    return segments.join('/');
  }

  String _baseServerPath(String serverUrl) {
    final uri = Uri.parse(serverUrl.trim());
    return '/${uri.pathSegments.where((segment) => segment.isNotEmpty).join('/')}';
  }

  String _safeError(Object error) {
    if (error is WebDavException) return error.toString();
    if (error is FormatException) return error.message.toString();
    if (error is StateError) return error.message.toString();
    return 'WebDAV request failed: ${error.runtimeType}';
  }

  @override
  void dispose() {
    _httpClient.close();
    sourcesNotifier.dispose();
    syncProgressNotifier.dispose();
    transferProgressNotifier.dispose();
    snapshotRevisionNotifier.dispose();
    cacheRevisionNotifier.dispose();
    preloadCountNotifier.dispose();
    super.dispose();
  }
}
