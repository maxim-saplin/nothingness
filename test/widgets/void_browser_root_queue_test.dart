import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/controllers/library_controller.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/webdav_source.dart';
import 'package:nothingness/services/android_smart_roots.dart';
import 'package:nothingness/services/library_browser.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/widgets/void_browser.dart';
import 'package:provider/provider.dart';

import 'heroes/_test_helpers.dart';

const _source = WebDavSource(
  id: 'cloud',
  name: 'Cloud',
  serverUrl: 'https://example.com',
  username: 'user',
  folderPath: 'Music',
);
const _tracks = [
  AudioTrack(path: 'root.mp3', title: 'Root'),
  AudioTrack(path: 'nested.mp3', title: 'Nested'),
];

class _Controller extends LibraryController {
  _Controller({bool android = false, bool cloud = false, this.result = _tracks})
      : sources = ValueNotifier(cloud ? [_source] : []),
        super(
          libraryBrowser: LibraryBrowser(supportedExtensions: {'mp3'}),
          libraryService: LibraryService(),
          isAndroidOverride: android,
        ) {
    hasPermission = true;
    if (android) {
      androidSmartRootSections = const [
        SmartRootSection(deviceRoot: '/storage', entries: ['/storage/Music']),
      ];
    }
  }

  final ValueNotifier<List<WebDavSource>> sources;
  final List<AudioTrack> result;
  String? requestedPath;
  String? openedPath;

  @override
  List<WebDavSource> get webDavSources => sources.value;
  @override
  ValueListenable<List<WebDavSource>> get webDavSourcesNotifier => sources;
  @override
  String webDavSourceRootPath(WebDavSource source) => 'webdav://cloud/Music';
  @override
  Future<List<AudioTrack>> webDavTracksInTree(String path) async {
    requestedPath = path;
    return result;
  }
  @override
  Future<List<AudioTrack>> androidTracksInTree(String path) async {
    requestedPath = path;
    return result;
  }
  @override
  Future<void> loadFolder(String path) async => openedPath = path;
  @override
  void dispose() {
    sources.dispose();
    super.dispose();
  }
}

class _Player extends FakeAudioPlayerProvider {
  List<AudioTrack>? queued;
  bool? shuffled;
  String? scannedPath;

  @override
  Future<List<AudioTrack>> scanFolder(String path) async {
    scannedPath = path;
    return _tracks;
  }

  @override
  Future<void> setQueue(List<AudioTrack> tracks,
      {int startIndex = 0, bool shuffle = false, int? guardActionGen}) async {
    queued = tracks;
    shuffled = shuffle;
  }
}

void main() {
  Future<void> showBrowser(
    WidgetTester tester,
    _Controller controller,
    _Player player,
  ) async {
    await tester.pumpWidget(wrapWithProvider(
      player,
      ChangeNotifierProvider<LibraryController>.value(
        value: controller,
        child: VoidBrowser(controller: controller),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('WebDAV root long-press shuffles all descendants', (tester) async {
    final controller = _Controller(cloud: true);
    final player = _Player();
    addTearDown(controller.dispose);
    await showBrowser(tester, controller, player);

    final row = find.byKey(const ValueKey('void-webdav-root:cloud'));
    await tester.longPress(row);
    await tester.pumpAndSettle();
    expect(controller.requestedPath, 'webdav://cloud/Music');
    expect(controller.openedPath, isNull);
    expect(player.queued, _tracks);
    expect(player.shuffled, isTrue);

    await tester.tap(row);
    expect(controller.openedPath, 'webdav://cloud/Music');
  });

  testWidgets('empty root leaves the existing queue untouched', (tester) async {
    final controller = _Controller(cloud: true, result: const []);
    final player = _Player()..queued = _tracks;
    addTearDown(controller.dispose);
    await showBrowser(tester, controller, player);

    await tester.longPress(find.byKey(const ValueKey('void-webdav-root:cloud')));
    await tester.pumpAndSettle();
    expect(controller.requestedPath, 'webdav://cloud/Music');
    expect(player.queued, _tracks);
    expect(player.shuffled, isNull);
  });

  testWidgets('Android smart root long-press shuffles all descendants', (tester) async {
    final controller = _Controller(android: true);
    final player = _Player();
    addTearDown(controller.dispose);
    await showBrowser(tester, controller, player);

    await tester.longPress(find.byKey(const ValueKey('void-smart:/storage/Music')));
    await tester.pumpAndSettle();
    expect(controller.requestedPath, '/storage/Music');
    expect(controller.openedPath, isNull);
    expect(player.queued, _tracks);
    expect(player.shuffled, isTrue);
  });

  testWidgets('filesystem root long-press shuffles all descendants', (tester) async {
    final roots = LibraryService().rootsNotifier;
    final previous = roots.value;
    roots.value = {'/library': '/library'};
    addTearDown(() => roots.value = previous);
    final controller = _Controller();
    final player = _Player();
    addTearDown(controller.dispose);
    await showBrowser(tester, controller, player);

    await tester.longPress(find.byKey(const ValueKey('void-root:/library')));
    await tester.pumpAndSettle();
    expect(player.scannedPath, '/library');
    expect(controller.openedPath, isNull);
    expect(player.queued, _tracks);
    expect(player.shuffled, isTrue);
  });
}
