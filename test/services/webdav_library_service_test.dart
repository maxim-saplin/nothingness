import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nothingness/models/webdav_source.dart';
import 'package:nothingness/services/webdav_library_service.dart';
import 'package:nothingness/services/webdav_track_path.dart';

void main() {
  late Directory rootDir;
  late Directory cacheDir;
  late _RemoteFixture remote;
  late _MemorySecretStore secretStore;
  late WebDavLibraryService service;

  setUp(() async {
    rootDir = await Directory.systemTemp.createTemp('webdav_hive_test');
    cacheDir = Directory('${rootDir.path}/cache');
    await Hive.close();
    Hive.init(rootDir.path);
    remote = _RemoteFixture();
    secretStore = _MemorySecretStore();
    service = WebDavLibraryService(
      secretStore: secretStore,
      httpClient: MockClient(remote.handle),
      cacheDirectory: () async => cacheDir,
    );
    await service.init();
  });

  tearDown(() async {
    service.dispose();
    await Hive.close();
    if (rootDir.existsSync()) await rootDir.delete(recursive: true);
  });

  test('account root URL is built safely and requires HTTPS', () {
    expect(
      WebDavLibraryService.accountRootUri(
        serverUrl: 'https://cloud.example/nextcloud/',
        username: 'alice',
      ).toString(),
      'https://cloud.example/nextcloud/remote.php/dav/files/alice',
    );
    expect(
      () => WebDavLibraryService.accountRootUri(
        serverUrl: 'http://cloud.example',
        username: 'alice',
      ),
      throwsFormatException,
    );
    expect(
      () => WebDavLibraryService.accountRootUri(
        serverUrl: 'https://alice:secret@cloud.example',
        username: 'alice',
      ),
      throwsFormatException,
    );
  });

  test(
    'indexes, searches, reuses audio and refreshes changed directories',
    () async {
      final source = await _addSource(service);
      await service.refreshSource(source.id);

      final rootPath = service.sourceRootPath(source);
      final root = await service.listFolder(rootPath);
      expect(root.folders.map((folder) => folder.name), ['Live']);
      expect(root.tracks.map((track) => track.title), ['Hello']);
      expect(root.tracks.single.artist, 'Adele');
      expect((await service.tracksInTree(rootPath)), hasLength(2));
      expect(
        (await service.searchTracks('adele')).single.path,
        root.tracks.single.path,
      );
      expect(
        await service.snapshotSizeBytes(sourceId: source.id),
        greaterThan(0),
      );
      expect(await service.audioCacheSizeBytes(), 0);
      expect(service.syncProgressNotifier.value[source.id]?.isComplete, isTrue);

      final storedSource =
          Hive.box<dynamic>('webDavSources').get(source.id) as Map;
      expect(storedSource, isNot(contains('appPassword')));
      expect(jsonEncode(storedSource), isNot(contains('test-app-password')));
      expect(
        secretStore.values['webdav.appPassword.${source.id}'],
        'test-app-password',
      );

      remote.resetCounters();
      await service.refreshSource(source.id);
      expect(remote.depthZeroRootRequests, 1);
      expect(remote.rootListingRequests, 0);
      expect(remote.liveListingRequests, 0);

      final trackPath = root.tracks.single.path;
      service.pin(trackPath);
      final localPath = await service.resolveLocalPath(trackPath);
      expect(await File(localPath).readAsBytes(), [1, 2]);
      expect(await service.resolveLocalPath(trackPath), localPath);
      expect(remote.downloadRequests, 1);
      expect(await service.audioCacheSizeBytes(), 2);
      service.unpin(trackPath);

      remote.version = 2;
      await service.refreshSource(source.id);
      final updatedRoot = await service.listFolder(rootPath);
      expect(updatedRoot.tracks.map((track) => track.title).toSet(), {
        'Hello',
        'Jóga',
      });
      expect(remote.rootListingRequests, 1);
      expect(remote.liveListingRequests, 0);
      expect(await File(localPath).exists(), isFalse);
      expect(await service.audioCacheSizeBytes(), 0);

      await Hive.box<dynamic>('webDavMeta').put('cacheLimitBytes', 2);
      final changedPath = updatedRoot.tracks
          .singleWhere((track) => track.title == 'Hello')
          .path;
      service.pin(changedPath);
      final updatedLocalPath = await service.resolveLocalPath(changedPath);
      expect(await File(updatedLocalPath).readAsBytes(), [3, 4, 5]);

      final jogaPath = updatedRoot.tracks
          .singleWhere((track) => track.title == 'Jóga')
          .path;
      service.pin(jogaPath);
      final jogaLocalPath = await service.resolveLocalPath(jogaPath);
      expect(await File(jogaLocalPath).readAsBytes(), [9, 8, 7]);
      expect(remote.downloadRequests, 3);
      expect(
        await service.audioCacheSizeBytes(),
        6,
        reason: 'pinned current/next tracks may exceed the cache limit',
      );

      final currentPruned = _nextCacheChange(service);
      service.unpin(changedPath);
      await currentPruned;
      expect(await File(updatedLocalPath).exists(), isFalse);
      expect(await File(jogaLocalPath).exists(), isTrue);

      final nextPruned = _nextCacheChange(service);
      service.unpin(jogaPath);
      await nextPruned;
      expect(await service.audioCacheSizeBytes(), 0);
    },
  );

  test('coalesces concurrent downloads for the same track', () async {
    final source = await _addSource(service);
    await service.refreshSource(source.id);
    final track = (await service.listFolder(service.sourceRootPath(source))).tracks.single;
    service.pin(track.path);
    final paths = await Future.wait([
      service.resolveLocalPath(track.path),
      service.resolveLocalPath(track.path, preloading: true),
    ]);
    expect(paths[0], paths[1]);
    expect(remote.downloadRequests, 1);
    expect(await File(paths[0]).readAsBytes(), [1, 2]);
  });

  test('pruning removes stale entries even below the cache limit', () async {
    final box = Hive.box<dynamic>('webDavAudioCache');
    final oldFile = File('${cacheDir.path}/old.mp3');
    final staleFile = File('${cacheDir.path}/stale.mp3');
    await oldFile.writeAsBytes([1]);
    await staleFile.writeAsBytes([2]);
    await box.put('old', {
      'trackPath': 'webdav://source/old', 'filePath': oldFile.path,
      'size': 1, 'lastUsedMs': 1, 'stale': false,
    });
    await box.put('stale', {
      'trackPath': 'webdav://source/stale', 'filePath': staleFile.path,
      'size': 1, 'lastUsedMs': 2, 'stale': true,
    });
    await service.setCacheLimitMiB(512);
    expect(await oldFile.exists(), isTrue);
    expect(await staleFile.exists(), isFalse);
  });

  test(
    'cache entries keep remote IDs and clear removes credentials and index',
    () async {
      final source = await _addSource(service);
      await service.refreshSource(source.id);
      final track = (await service.listFolder(
        service.sourceRootPath(source),
      )).tracks.single;
      final expectedId = WebDavTrackPath.encode(
        source.id,
        'Music/Adele - Hello.flac',
      );
      expect(track.path, expectedId);

      service.pin(track.path);
      final cachedPath = await service.resolveLocalPath(track.path);
      await service.removeSource(source.id);

      expect(service.sources, isEmpty);
      expect(secretStore.values, isEmpty);
      expect(await service.snapshotSizeBytes(), 0);
      expect(
        await File(cachedPath).exists(),
        isTrue,
        reason:
            'an in-use current track stays pinned until playback releases it',
      );

      service.unpin(track.path);
      await service.clearUnusedAudioCache();
      expect(await File(cachedPath).exists(), isFalse);
    },
  );
}

Future<void> _nextCacheChange(WebDavLibraryService service) {
  final revision = service.cacheRevisionNotifier.value;
  final completer = Completer<void>();
  late void Function() listener;
  listener = () {
    if (service.cacheRevisionNotifier.value > revision) {
      service.cacheRevisionNotifier.removeListener(listener);
      completer.complete();
    }
  };
  service.cacheRevisionNotifier.addListener(listener);
  return completer.future
      .timeout(const Duration(seconds: 3))
      .whenComplete(
        () => service.cacheRevisionNotifier.removeListener(listener),
      );
}

Future<WebDavSource> _addSource(WebDavLibraryService service) =>
    service.addSource(
      name: '',
      serverUrl: 'https://cloud.example',
      username: 'alice',
      appPassword: 'test-app-password',
      folderPath: 'Music',
    );

class _MemorySecretStore implements WebDavSecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _RemoteFixture {
  int version = 1;
  int rootListingRequests = 0;
  int liveListingRequests = 0;
  int depthZeroRootRequests = 0;
  int downloadRequests = 0;

  void resetCounters() {
    rootListingRequests = 0;
    liveListingRequests = 0;
    depthZeroRootRequests = 0;
    downloadRequests = 0;
  }

  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'PROPFIND') {
      final depth = request.headers['Depth'];
      if (depth == '0') {
        if (request.url.path.endsWith('/Music')) {
          depthZeroRootRequests++;
          return _xmlResponse(
            _selfDirectoryXml(
              'Music',
              '"root-v$version"',
              accountPath: 'Music',
            ),
          );
        }
        return http.Response('', 404);
      }
      if (request.url.path.endsWith('/Music/Live')) {
        liveListingRequests++;
        return _xmlResponse(_liveXml);
      }
      if (request.url.path.endsWith('/Music')) {
        rootListingRequests++;
        return _xmlResponse(_rootXml(version));
      }
      return http.Response('', 404);
    }

    if (request.method == 'GET') {
      downloadRequests++;
      if (request.url.pathSegments.last == 'Adele - Hello.flac') {
        return http.Response.bytes(
          version == 1 ? [1, 2] : [3, 4, 5],
          200,
          headers: {'etag': '"direct-v$version"'},
        );
      }
      if (request.url.pathSegments.last == 'Björk - Jóga.opus') {
        return http.Response.bytes(
          [9, 8, 7],
          200,
          headers: {'etag': '"joga-v$version"'},
        );
      }
      return http.Response('', 404);
    }
    return http.Response('', 405);
  }
}

http.Response _xmlResponse(String body) => http.Response(
  body,
  207,
  headers: {'content-type': 'application/xml; charset=utf-8'},
);

String _selfDirectoryXml(
  String name,
  String etag, {
  required String accountPath,
}) =>
    '''<D:multistatus xmlns:D="DAV:"><D:response><D:href>/remote.php/dav/files/alice/$accountPath/</D:href><D:propstat><D:prop><D:displayname>$name</D:displayname><D:resourcetype><D:collection/></D:resourcetype><D:getetag>$etag</D:getetag></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>''';

String _rootXml(int version) {
  final files = <String>[
    _fileResponse(
      'Music/Adele%20-%20Hello.flac',
      'Adele - Hello.flac',
      etag: version == 1 ? '"direct-v1"' : '"direct-v2"',
      size: version == 1 ? 2 : 3,
    ),
    if (version >= 2)
      _fileResponse(
        'Music/Bj%C3%B6rk%20-%20J%C3%B3ga.opus',
        'Björk - Jóga.opus',
        etag: '"joga-v$version"',
        size: 3,
      ),
    _fileResponse(
      'Music/notes.txt',
      'notes.txt',
      etag: '"text-v$version"',
      size: 10,
    ),
  ].join();
  return '''<D:multistatus xmlns:D="DAV:">
    <D:response><D:href>/remote.php/dav/files/alice/Music/</D:href><D:propstat><D:prop><D:displayname>Music</D:displayname><D:resourcetype><D:collection/></D:resourcetype><D:getetag>"root-v$version"</D:getetag></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
    <D:response><D:href>/remote.php/dav/files/alice/Music/Live/</D:href><D:propstat><D:prop><D:displayname>Live</D:displayname><D:resourcetype><D:collection/></D:resourcetype><D:getetag>"live-v1"</D:getetag></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
    $files
  </D:multistatus>''';
}

String _fileResponse(
  String href,
  String name, {
  required String etag,
  required int size,
}) =>
    '''<D:response><D:href>/remote.php/dav/files/alice/$href</D:href><D:propstat><D:prop><D:displayname>$name</D:displayname><D:resourcetype/><D:getcontentlength>$size</D:getcontentlength><D:getetag>$etag</D:getetag><D:getcontenttype>audio/ogg</D:getcontenttype></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>''';

const _liveXml = '''<D:multistatus xmlns:D="DAV:">
  <D:response><D:href>/remote.php/dav/files/alice/Music/Live/</D:href><D:propstat><D:prop><D:displayname>Live</D:displayname><D:resourcetype><D:collection/></D:resourcetype><D:getetag>"live-v1"</D:getetag></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
  <D:response><D:href>/remote.php/dav/files/alice/Music/Live/Live%20-%20Concert.mp3</D:href><D:propstat><D:prop><D:displayname>Live - Concert.mp3</D:displayname><D:resourcetype/><D:getcontentlength>1</D:getcontentlength><D:getetag>"concert-v1"</D:getetag><D:getcontenttype>audio/mpeg</D:getcontenttype></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
</D:multistatus>''';
