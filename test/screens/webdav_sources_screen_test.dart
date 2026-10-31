import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nothingness/models/webdav_source.dart';
import 'package:nothingness/screens/webdav_sources_screen.dart';
import 'package:nothingness/services/webdav_client.dart';
import 'package:nothingness/services/webdav_library_service.dart';

void main() {
  late _MemorySecretStore secretStore;
  late _FakeWebDavService service;

  setUp(() {
    secretStore = _MemorySecretStore();
    service = _FakeWebDavService(secretStore: secretStore);
  });

  tearDown(() {
    service.dispose();
  });

  testWidgets('connects a source and shows separate local storage controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(home: WebDavSourcesScreen(service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No WebDAV sources configured.'), findsOneWidget);
    expect(find.text('Metadata snapshot'), findsOneWidget);
    expect(find.text('Downloaded audio'), findsOneWidget);
    expect(find.byKey(const ValueKey('webdav-cache-limit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('webdav-add-source')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('webdav-server')),
      'https://cloud.example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('webdav-username')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const ValueKey('webdav-password')),
      'test-app-password',
    );
    await tester.enterText(
      find.byKey(const ValueKey('webdav-folder')),
      'Music',
    );
    await tester.tap(find.byKey(const ValueKey('webdav-save-source')));
    await tester.pumpAndSettle();

    final source = service.sources.single;
    final sourceCard = find.byKey(ValueKey('webdav-source-${source.id}'));
    expect(
      find.descendant(of: sourceCard, matching: find.text('Music')),
      findsOneWidget,
    );
    expect(secretStore.values.values.single, 'test-app-password');
    expect(source.toJson(), isNot(contains('appPassword')));

    await tester.tap(find.byKey(ValueKey('webdav-remove-${source.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Remove source?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('No WebDAV sources configured.'), findsOneWidget);
    expect(secretStore.values, isEmpty);
  });

  testWidgets('updates storage sizes when snapshot and cache change', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WebDavSourcesScreen(service: service)),
    );
    await tester.pumpAndSettle();

    service.snapshotBytes = 2048;
    service.audioBytes = 3 * 1024 * 1024;
    service.snapshotRevisionNotifier.value++;
    service.cacheRevisionNotifier.value++;
    await tester.pumpAndSettle();

    expect(find.text('2 KiB'), findsOneWidget);
    expect(find.text('3.0 MiB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preload slider shows default and saves both boundaries', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WebDavSourcesScreen(service: service)),
    );
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('webdav-preload-count'));
    expect(find.text('Upcoming tracks to preload: 3'), findsOneWidget);
    expect(tester.widget<Slider>(slider).min, 1);
    expect(tester.widget<Slider>(slider).max, 10);
    expect(tester.widget<Slider>(slider).divisions, 9);

    await tester.tapAt(tester.getTopRight(slider) - const Offset(24, -20));
    await tester.pumpAndSettle();
    expect(service.preloadCountNotifier.value, 10);
    expect(find.text('Upcoming tracks to preload: 10'), findsOneWidget);
    await tester.tapAt(tester.getTopLeft(slider) + const Offset(24, 20));
    await tester.pumpAndSettle();
    expect(service.preloadCountNotifier.value, 1);
    expect(find.text('Upcoming tracks to preload: 1'), findsOneWidget);
  });

  testWidgets('failed preload setting save restores the persisted value', (tester) async {
    service.failPreloadSave = true;
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WebDavSourcesScreen(service: service)),
    );
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('webdav-preload-count'));
    await tester.tapAt(tester.getTopRight(slider) - const Offset(24, -20));
    await tester.pumpAndSettle();
    expect(service.preloadCountNotifier.value, 3);
    expect(find.text('Upcoming tracks to preload: 3'), findsOneWidget);
    expect(find.textContaining('Could not save preload setting'), findsOneWidget);
  });

  testWidgets('explains that HTTP sources are not allowed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WebDavSourcesScreen(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('webdav-add-source')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('webdav-server')), 'http://cloud.example');
    await tester.enterText(find.byKey(const ValueKey('webdav-username')), 'alice');
    await tester.enterText(find.byKey(const ValueKey('webdav-password')), 'test-password');
    await tester.tap(find.byKey(const ValueKey('webdav-save-source')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use an HTTPS server URL'), findsOneWidget);
    expect(service.sources, isEmpty);
  });

  testWidgets('connection errors do not reveal the app password', (
    tester,
  ) async {
    service.statusCode = 401;
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(home: WebDavSourcesScreen(service: service)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('webdav-add-source')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('webdav-server')),
      'https://cloud.example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('webdav-username')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const ValueKey('webdav-password')),
      'private-secret-value',
    );
    await tester.enterText(
      find.byKey(const ValueKey('webdav-folder')),
      'Music',
    );
    await tester.tap(find.byKey(const ValueKey('webdav-save-source')));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 401'), findsOneWidget);
    final dialogText = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Text),
          ),
        )
        .map((widget) => widget.data ?? '')
        .join(' ');
    expect(dialogText, isNot(contains('private-secret-value')));
    expect(secretStore.values, isEmpty);
  });
}

class _FakeWebDavService extends WebDavLibraryService {
  _FakeWebDavService({required this.secretStore})
    : super(
        secretStore: secretStore,
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

  final _MemorySecretStore secretStore;
  int statusCode = 207;
  int snapshotBytes = 0;
  int audioBytes = 0;
  bool failPreloadSave = false;
  int _nextId = 1;

  @override
  int get cacheLimitBytes => 512 * 1024 * 1024;

  @override
  Future<void> init() async {}

  @override
  Future<WebDavSource> addSource({
    required String name,
    required String serverUrl,
    required String username,
    required String appPassword,
    required String folderPath,
  }) async {
    WebDavLibraryService.accountRootUri(serverUrl: serverUrl, username: username);
    if (statusCode != 207) {
      throw WebDavException(
        'Could not list WebDAV folder',
        statusCode: statusCode,
      );
    }
    final folder = folderPath.trim().replaceAll('\\', '/');
    final source = WebDavSource(
      id: 'test-source-${_nextId++}',
      name: name.trim().isNotEmpty
          ? name.trim()
          : (folder.isEmpty ? username : folder.split('/').last),
      serverUrl: serverUrl,
      username: username,
      folderPath: folder,
    );
    await secretStore.write('webdav.appPassword.${source.id}', appPassword);
    sourcesNotifier.value = [...sources, source];
    syncProgressNotifier.value = {
      ...syncProgressNotifier.value,
      source.id: WebDavSyncProgress(
        sourceId: source.id,
        foldersScanned: 1,
        tracksIndexed: 0,
        isComplete: true,
      ),
    };
    return source;
  }

  @override
  Future<void> removeSource(String sourceId) async {
    await secretStore.delete('webdav.appPassword.$sourceId');
    sourcesNotifier.value = sources
        .where((source) => source.id != sourceId)
        .toList();
    final progress = {...syncProgressNotifier.value}..remove(sourceId);
    syncProgressNotifier.value = progress;
  }

  @override
  Future<void> refreshSource(String sourceId) async {}

  @override
  Future<int> snapshotSizeBytes({String? sourceId}) async => snapshotBytes;

  @override
  Future<int> audioCacheSizeBytes({String? sourceId}) async => audioBytes;

  @override
  Future<void> setCacheLimitMiB(int mebibytes) async {}

  @override
  Future<void> setPreloadCount(int count) async {
    if (failPreloadSave) throw StateError('storage unavailable');
    preloadCountNotifier.value = count;
  }

  @override
  Future<void> clearUnusedAudioCache({String? sourceId}) async {}
}

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
