import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nothingness/services/platform_channels.dart';
import 'package:nothingness/services/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _mediaChannel = MethodChannel('com.saplin.nothingness/media');
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

final _newerRelease = <String, Object>{
  'tag_name': 'v3.15.0+83',
  'assets': [
    {
      'name': 'nothingness-android-3.15.0+83.apk',
      'browser_download_url': 'https://example.test/nothingness.apk',
    },
  ],
};

/// Fake GitHub: serves [release] for the API call and [apk] for the download,
/// split in two chunks so progress is observable. [hits] records every URL.
MockClient _client({
  Map<String, Object> release = const {},
  int apiStatus = 200,
  List<int> apk = const [],
  List<Uri>? hits,
}) =>
    MockClient.streaming((request, _) async {
      hits?.add(request.url);
      if (request.url.host == 'api.github.com') {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(release))),
          apiStatus,
        );
      }
      final half = apk.length ~/ 2;
      return http.StreamedResponse(
        Stream.fromIterable([apk.sublist(0, half), apk.sublist(half)]),
        200,
        contentLength: apk.length,
      );
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = UpdateService();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tmp;
  late List<Uri> hits;

  setUp(() {
    service.reset();
    PackageInfo.setMockInitialValues(
      appName: 'nothingness',
      packageName: 'com.saplin.nothingness',
      version: '3.14.14',
      buildNumber: '82',
      buildSignature: '',
    );
    tmp = Directory.systemTemp.createTempSync('update_service_test_');
    hits = [];
    messenger.setMockMethodCallHandler(_pathChannel, (_) async => tmp.path);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_mediaChannel, null);
    messenger.setMockMethodCallHandler(_pathChannel, null);
    PlatformChannels.isAndroid = false;
    tmp.deleteSync(recursive: true);
  });

  group('parseRelease', () {
    test('returns the version and APK url of a newer build', () {
      final release = UpdateService.parseRelease(_newerRelease, 82);
      expect(release?.version, '3.15.0+83');
      expect(release?.url, Uri.parse('https://example.test/nothingness.apk'));
    });

    test('ignores releases that are not newer', () {
      expect(UpdateService.parseRelease(_newerRelease, 83), isNull);
      expect(UpdateService.parseRelease(_newerRelease, 84), isNull);
    });

    test('ignores tags without a numeric build suffix', () {
      final json = {..._newerRelease, 'tag_name': 'v3.15.0'};
      expect(UpdateService.parseRelease(json, 82), isNull);
    });

    test('ignores releases without a nothingness APK attached', () {
      final json = <String, Object>{
        'tag_name': 'v3.15.0+83',
        'assets': [
          {'name': 'source.zip', 'browser_download_url': 'https://example.test/s.zip'},
        ],
      };
      expect(UpdateService.parseRelease(json, 82), isNull);
    });
  });

  group('check', () {
    test('offers the update when a newer release exists', () async {
      await http.runWithClient(
        () => service.check(),
        () => _client(release: _newerRelease, hits: hits),
      );
      expect(service.phase.value, UpdatePhase.available);
      expect(service.version, '3.15.0+83');
    });

    test('does not query GitHub again within the hour', () async {
      final upToDate = <String, Object>{'tag_name': 'v3.14.14+82', 'assets': []};
      await http.runWithClient(
        () async {
          await service.check();
          await service.check();
        },
        () => _client(release: upToDate, hits: hits),
      );
      expect(hits, hasLength(1));
      expect(service.phase.value, UpdatePhase.none);
    });

    test('stays quiet when GitHub rejects the request', () async {
      await http.runWithClient(
        () => service.check(),
        () => _client(apiStatus: 403),
      );
      expect(service.phase.value, UpdatePhase.none);
    });

    test('stays quiet when offline', () async {
      await http.runWithClient(
        () => service.check(),
        () => MockClient.streaming(
          (request, _) async => throw const SocketException('offline'),
        ),
      );
      expect(service.phase.value, UpdatePhase.none);
    });
  });

  group('start', () {
    Future<void> offerUpdate(List<int> apk) => http.runWithClient(
          () => service.check(),
          () => _client(release: _newerRelease, apk: apk),
        );

    test('downloads, commits to the installer and cleans up', () async {
      final apk = List.filled(10, 7);
      await offerUpdate(apk);
      PlatformChannels.isAndroid = true;

      final calls = <String>[];
      String? installedPath;
      var fileExistedAtCommit = false;
      messenger.setMockMethodCallHandler(_mediaChannel, (call) async {
        calls.add(call.method);
        if (call.method == 'installApk') {
          installedPath = (call.arguments as Map)['path'] as String;
          fileExistedAtCommit = File(installedPath!).existsSync();
        }
        return true;
      });

      final phases = <UpdatePhase>[];
      final percents = <int>[];
      void onPhase() => phases.add(service.phase.value);
      void onPercent() => percents.add(service.percent.value);
      service.phase.addListener(onPhase);
      service.percent.addListener(onPercent);
      addTearDown(() {
        service.phase.removeListener(onPhase);
        service.percent.removeListener(onPercent);
      });

      await http.runWithClient(
        () => service.start(),
        () => _client(release: _newerRelease, apk: apk, hits: hits),
      );

      expect(calls, ['ensureInstallPermission', 'installApk']);
      expect(installedPath, '${tmp.path}/update/update.apk');
      expect(fileExistedAtCommit, isTrue);
      expect(percents, [50, 100]);
      expect(phases, [
        UpdatePhase.downloading,
        UpdatePhase.installing,
        UpdatePhase.available,
      ]);
      expect(Directory('${tmp.path}/update').existsSync(), isFalse);
    });

    test('downloads nothing when install permission is refused', () async {
      await offerUpdate(const [1, 2]);
      PlatformChannels.isAndroid = true;

      final calls = <String>[];
      messenger.setMockMethodCallHandler(_mediaChannel, (call) async {
        calls.add(call.method);
        return false;
      });

      hits.clear();
      await http.runWithClient(
        () => service.start(),
        () => _client(apk: const [1, 2], hits: hits),
      );

      expect(calls, ['ensureInstallPermission']);
      expect(hits, isEmpty);
      expect(service.phase.value, UpdatePhase.available);
    });
  });

  group('sweep', () {
    test('abandons installer sessions and removes a leftover download', () async {
      PlatformChannels.isAndroid = true;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(_mediaChannel, (call) async {
        calls.add(call.method);
        return null;
      });
      final dir = Directory('${tmp.path}/update')..createSync();
      File('${dir.path}/update.apk').writeAsBytesSync([1, 2, 3]);

      await service.sweep();

      expect(calls, ['abandonInstallSessions']);
      expect(dir.existsSync(), isFalse);
    });

    test('is a no-op when nothing was downloaded', () async {
      await expectLater(service.sweep(), completes);
    });
  });
}
