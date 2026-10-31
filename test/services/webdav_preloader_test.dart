import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';
import 'package:nothingness/services/track_file_resolver.dart';
import 'package:nothingness/services/webdav_library_service.dart';
import 'package:nothingness/services/webdav_preloader.dart';

import '../support/pump_until.dart';
import 'mock_audio_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PlaylistStore playlist;
  late _Resolver resolver;
  late ValueNotifier<int> count;
  late WebDavPreloader preloader;
  var playlistDisposed = false;

  List<AudioTrack> tracks(int length) => List.generate(
    length,
    (i) => AudioTrack(path: 'webdav://source/$i', title: '$i'),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('webdav_preload_');
    playlistDisposed = false;
    Hive.init(directory.path);
    playlist = PlaylistStore(hiveInitializer: () async {});
    await playlist.init();
    resolver = _Resolver();
    count = ValueNotifier(3);
    preloader = WebDavPreloader(
      playlist: playlist,
      resolver: resolver,
      count: count,
    );
  });

  tearDown(() async {
    preloader.dispose();
    count.dispose();
    if (!playlistDisposed) await playlist.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'downloads the selected number in queue order and follows changes',
    () async {
      final queue = tracks(12);
      await playlist.setQueue(queue);
      preloader.setActivePath(queue.first.path);
      await pumpUntil(() => resolver.calls.length == 3);
      expect(resolver.calls, queue.skip(1).take(3).map((t) => t.path));
      expect(
        resolver.pins.keys.toSet(),
        queue.skip(1).take(3).map((t) => t.path).toSet(),
      );

      count.value = 10;
      await pumpUntil(() => resolver.calls.length == 10);
      expect(resolver.calls, queue.skip(1).take(10).map((t) => t.path));

      count.value = 1;
      expect(resolver.pins.keys, [queue[1].path]);
      await playlist.setCurrentOrderIndex(10);
      expect(resolver.pins, isEmpty);
      preloader.setActivePath(queue[10].path);
      await pumpUntil(() => resolver.calls.last == queue[11].path);
      expect(resolver.pins.keys, [queue[11].path]);

      await playlist.setCurrentOrderIndex(11);
      preloader.setActivePath(queue[11].path);
      expect(resolver.pins, isEmpty);
    },
  );

  test(
    'queue replacement cancels stale work and keeps in-flight file pinned',
    () async {
      resolver.block = Completer<void>();
      final queue = tracks(5);
      await playlist.setQueue(queue);
      preloader.setActivePath(queue[0].path);
      expect(resolver.calls, [queue[1].path]);
      expect(resolver.pins[queue[1].path], 2);

      await playlist.setQueue([queue[4], queue[3]]);
      expect(resolver.pins, {queue[1].path: 1});
      preloader.setActivePath(queue[4].path);
      expect(resolver.pins[queue[3].path], 1);
      resolver.block!.complete();
      await pumpUntil(() => resolver.calls.contains(queue[3].path));
      expect(resolver.calls, [queue[1].path, queue[3].path]);
      await pumpUntil(() => !resolver.pins.containsKey(queue[1].path));
      expect(resolver.pins, {queue[3].path: 1});
    },
  );

  test('reshuffle follows the new playback order', () async {
    final queue = tracks(12);
    await playlist.setQueue(queue);
    preloader.setActivePath(queue.first.path);
    await pumpUntil(() => resolver.calls.length == 3);
    await playlist.reshuffle(keepBaseIndex: 0);
    final index = playlist.currentOrderIndexNotifier.value!;
    final expected = [
      for (var i = index + 1; i < playlist.length && i <= index + 3; i++)
        playlist.trackForOrderIndex(i)!.path,
    ];
    await pumpUntil(() => expected.every(resolver.calls.contains));
    expect(resolver.pins.keys.toSet(), expected.toSet());
    expect(expected.every(resolver.calls.contains), isTrue);
  });

  test(
    'skips local and duplicate paths, and continues after a failed download',
    () async {
      resolver.fail.add('webdav://source/1');
      final queue = [
        ...tracks(2),
        const AudioTrack(path: '/local.mp3', title: 'local'),
        const AudioTrack(path: 'webdav://source/1', title: 'duplicate'),
        const AudioTrack(path: 'webdav://source/4', title: 'four'),
      ];
      count.value = 4;
      await playlist.setQueue(queue);
      preloader.setActivePath(queue[0].path);
      await pumpUntil(() => resolver.calls.length == 2);
      expect(resolver.calls, ['webdav://source/1', 'webdav://source/4']);
      preloader.setActivePath(null);
      await pumpUntil(() => resolver.pins.isEmpty);
      expect(resolver.pins, isEmpty);
    },
  );

  test(
    'controller updates preloading after playback and settings changes',
    () async {
      preloader.dispose();
      final service = _FakeWebDavService();
      final transport = MockAudioTransport();
      final controller = PlaybackController(
        transport: transport,
        playlist: playlist,
        webDavService: service,
      );
      final queue = tracks(5);
      await playlist.setQueue(queue);
      await controller.init();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.calls, isEmpty, reason: 'restoring a queue does not load audio');
      await controller.setQueue(queue);
      await pumpUntil(() => service.calls.length == 3);
      expect(service.calls, queue.skip(1).take(3).map((t) => t.path));
      expect(transport.preloadCalls, contains(queue[1].path));

      service.preloadCountNotifier.value = 1;
      expect(service.pins.keys, [queue[1].path]);
      await controller.playFromQueueIndex(3);
      await pumpUntil(() => service.calls.contains(queue[4].path));
      expect(service.pins.keys, [queue[4].path]);
      await controller.playOneShot(
        const AudioTrack(path: '/one-shot.mp3', title: 'one-shot'),
      );
      expect(service.pins, isEmpty);
      await controller.shutdown();
      playlistDisposed = true;
      expect(service.pins, isEmpty);
      service.dispose();
    },
  );
}

class _Resolver implements TrackFileResolver {
  final List<String> calls = [];
  final Map<String, int> pins = {};
  final Set<String> fail = {};
  Completer<void>? block;

  @override
  bool supports(String path) => path.startsWith('webdav://');

  @override
  void pin(String path) => pins.update(path, (n) => n + 1, ifAbsent: () => 1);

  @override
  void unpin(String path) {
    final count = pins[path]!;
    if (count == 1) {
      pins.remove(path);
    } else {
      pins[path] = count - 1;
    }
  }

  @override
  Future<String> resolveLocalPath(
    String path, {
    bool preloading = false,
  }) async {
    expect(preloading, isTrue);
    calls.add(path);
    await block?.future;
    if (fail.contains(path)) throw StateError('download failed');
    return path;
  }
}

class _FakeWebDavService extends WebDavLibraryService {
  final _resolver = _Resolver();
  List<String> get calls => _resolver.calls;
  Map<String, int> get pins => _resolver.pins;

  @override
  bool supports(String path) => _resolver.supports(path);
  @override
  void pin(String path) => _resolver.pin(path);
  @override
  void unpin(String path) => _resolver.unpin(path);
  @override
  Future<String> resolveLocalPath(String path, {bool preloading = false}) =>
      _resolver.resolveLocalPath(path, preloading: preloading);
}
