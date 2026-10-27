import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/supported_extensions.dart';
import 'package:nothingness/models/webdav_source.dart';
import 'package:nothingness/services/library_browser.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/services/webdav_library_service.dart';
import 'package:nothingness/services/webdav_track_path.dart';
import 'package:nothingness/controllers/library_controller.dart';

void main() {
  late _FakeWebDavService webDav;
  late LibraryController controller;

  setUp(() {
    webDav = _FakeWebDavService();
    webDav.sourcesNotifier.value = const [
      WebDavSource(
        id: 'source-1',
        name: 'Nextcloud',
        serverUrl: 'https://cloud.example',
        username: 'alice',
        folderPath: 'Music',
      ),
    ];
    controller = LibraryController(
      libraryBrowser: LibraryBrowser(
        supportedExtensions: SupportedExtensions.supportedExtensions,
      ),
      libraryService: LibraryService(),
      isAndroidOverride: false,
      webDavService: webDav,
    );
  });

  tearDown(() {
    controller.dispose();
    webDav.dispose();
  });

  test(
    'browses the cached WebDAV tree and navigates back to its source root',
    () async {
      final root = WebDavTrackPath.encode('source-1', 'Music');
      final live = WebDavTrackPath.encode('source-1', 'Music/Live');
      final trackPath = WebDavTrackPath.encode(
        'source-1',
        'Music/Live/Björk - Jóga.opus',
      );

      await controller.loadFolder(root);
      expect(controller.currentPath, root);
      expect(controller.folders.single.path, live);
      expect(controller.tracks.single.title, 'Hello');
      expect(controller.displayPath(root), 'Nextcloud/Music');

      await controller.loadFolder(live);
      expect(controller.tracks.single.path, trackPath);
      expect(controller.parentPath(trackPath), live);
      await controller.navigateUp();
      expect(controller.currentPath, root);

      await controller.navigateUp();
      expect(controller.currentPath, isNull);
      expect(controller.tracks, isEmpty);
    },
  );
}

class _FakeWebDavService extends WebDavLibraryService {
  _FakeWebDavService()
    : super(httpClient: MockClient((_) async => http.Response('', 500)));

  final _source = const WebDavSource(
    id: 'source-1',
    name: 'Nextcloud',
    serverUrl: 'https://cloud.example',
    username: 'alice',
    folderPath: 'Music',
  );
  final _hello = AudioTrack(
    path: 'webdav://source-1/Music/Adele%20-%20Hello.flac',
    title: 'Hello',
    artist: 'Adele',
  );
  final _joga = AudioTrack(
    path: 'webdav://source-1/Music/Live/Bj%C3%B6rk%20-%20J%C3%B3ga.opus',
    title: 'Jóga',
    artist: 'Björk',
  );

  @override
  Future<void> init() async {}

  @override
  WebDavSource? sourceForId(String sourceId) =>
      sourceId == _source.id ? _source : null;

  @override
  Future<LibraryListing> listFolder(String trackPath) async {
    if (WebDavTrackPath.relativePath(trackPath) == 'Music') {
      return LibraryListing(
        path: trackPath,
        folders: [
          LibraryFolder(
            path: WebDavTrackPath.encode(_source.id, 'Music/Live'),
            name: 'Live',
          ),
        ],
        tracks: [_hello],
      );
    }
    return LibraryListing(path: trackPath, folders: const [], tracks: [_joga]);
  }

  @override
  Future<void> refreshIfStale(String sourceId) async {}

  @override
  Future<List<AudioTrack>> tracksInTree(String trackPath) async => [
    _hello,
    _joga,
  ];
}
