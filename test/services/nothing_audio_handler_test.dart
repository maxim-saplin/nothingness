import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/nothing_audio_handler.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import 'mock_audio_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MockAudioTransport transport;
  late PlaybackController controller;
  late NothingAudioHandler handler;
  var testNumber = 0;

  List<AudioTrack> tracks(int count) => List.generate(
        count,
        (i) => AudioTrack(path: '/music/$i.mp3', title: 'Track $i'),
      );

  setUp(() async {
    testNumber++;
    tempDir = await Directory.systemTemp.createTemp('media_session_test');
    Hive.init(tempDir.path);
    transport = MockAudioTransport();
    controller = PlaybackController(
      transport: transport,
      playlist: PlaylistStore(
        hive: Hive,
        hiveInitializer: () async {},
        boxOpener: (hive) => hive.openBox<dynamic>('media_session_$testNumber'),
      ),
    );
    handler = NothingAudioHandler.forTesting(
      controller: controller,
      transport: transport,
    );
    await handler.ready;
  });

  tearDown(() async {
    await controller.shutdown();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('large queue stays full internally, with a stable bounded OS window', () async {
    await controller.setQueue(tracks(25764));
    expect(controller.queue, hasLength(25764));
    expect(handler.queue.value, hasLength(50));
    expect(handler.playbackState.value.queueIndex, 0);
    final publishedQueue = handler.queue.value;

    await handler.skipToNext();
    expect(controller.currentIndex, 1);
    expect(handler.playbackState.value.queueIndex, 1);
    expect(identical(handler.queue.value, publishedQueue), isTrue);
    expect(handler.mediaItem.value?.id, '/music/1.mp3');

    await handler.skipToPrevious();
    expect(controller.currentIndex, 0);
    expect(handler.playbackState.value.queueIndex, 0);
    expect(identical(handler.queue.value, publishedQueue), isTrue);

    await controller.playFromQueueIndex(50);
    expect(handler.queue.value, hasLength(50));
    expect(handler.queue.value.first.id, '/music/25.mp3');
    expect(handler.playbackState.value.queueIndex, 25);
    expect(handler.mediaItem.value?.id, '/music/50.mp3');

    await handler.skipToQueueItem(30);
    expect(controller.currentIndex, 55);
    expect(handler.playbackState.value.queueIndex, 30);
    expect(handler.mediaItem.value?.id, '/music/55.mp3');
    expect(controller.queue, hasLength(25764));

    await handler.skipToQueueItem(-1);
    await handler.skipToQueueItem(50);
    expect(controller.currentIndex, 55);

    await controller.playFromQueueIndex(25763);
    expect(handler.queue.value, hasLength(50));
    expect(handler.queue.value.last.id, '/music/25763.mp3');
    expect(handler.playbackState.value.queueIndex, 49);
    await handler.skipToNext();
    expect(controller.currentIndex, 25763);
    transport.emitPosition(const Duration(milliseconds: 500));
    await handler.skipToPrevious();
    expect(controller.currentIndex, 25762);
    expect(handler.playbackState.value.queueIndex, 48);
  });

  test('small and empty queues publish complete state without stale items', () async {
    await controller.setQueue(tracks(3), startIndex: 1);
    expect(handler.queue.value.map((item) => item.id),
        ['/music/0.mp3', '/music/1.mp3', '/music/2.mp3']);
    expect(handler.playbackState.value.queueIndex, 1);
    await handler.skipToQueueItem(2);
    expect(controller.currentIndex, 2);
    expect(handler.mediaItem.value?.id, '/music/2.mp3');

    await controller.setQueue(const []);
    expect(handler.queue.value, isEmpty);
    expect(handler.playbackState.value.queueIndex, isNull);
  });

  test('queue metadata updates even when track IDs stay the same', () async {
    await controller.setQueue(tracks(1));
    await controller.setQueue(const [
      AudioTrack(path: '/music/0.mp3', title: 'New title', artist: 'Artist'),
    ]);
    expect(handler.queue.value.single.title, 'New title');
    expect(handler.queue.value.single.artist, 'Artist');
  });

  test('shuffle and backward window shifts retain queue selection', () async {
    await controller.setQueue(tracks(125), startIndex: 90);
    expect(handler.queue.value.first.id, '/music/65.mp3');
    expect(handler.playbackState.value.queueIndex, 25);

    await controller.playFromQueueIndex(10);
    expect(handler.queue.value.first.id, '/music/0.mp3');
    expect(handler.playbackState.value.queueIndex, 10);

    await controller.shuffleQueue();
    final fullIndex = controller.currentIndex!;
    final localIndex = handler.playbackState.value.queueIndex!;
    expect(handler.queue.value[localIndex].id, controller.queue[fullIndex].path);
    final target = handler.queue.value[3].id;
    await handler.skipToQueueItem(3);
    expect(controller.queue[controller.currentIndex!].path, target);
    expect(handler.mediaItem.value?.id, target);
  });

  test('failure flags are published and cleared for visible tracks', () async {
    transport.pathsToFailOnLoad.add('/music/0.mp3');
    await controller.setQueue(tracks(2));
    expect(handler.queue.value.first.extras?['isNotFound'], isTrue);
    transport.pathsToFailOnLoad.clear();
    await controller.setQueue(tracks(2));
    expect(handler.queue.value.first.extras?['isNotFound'], isFalse);
  });

  test('duplicate paths still use the actual playback position', () async {
    await controller.setQueue(const [
      AudioTrack(path: '/same.mp3', title: 'First'),
      AudioTrack(path: '/same.mp3', title: 'Second'),
    ], startIndex: 1);
    expect(controller.currentIndex, 1);
    expect(handler.playbackState.value.queueIndex, 1);
    await handler.skipToQueueItem(0);
    expect(controller.currentIndex, 0);
    expect(handler.playbackState.value.queueIndex, 0);
  });

  test('one-shot playback does not identify a queue item', () async {
    await controller.setQueue(tracks(3));
    await controller.playOneShot(const AudioTrack(path: '/other.mp3', title: 'Other'));
    expect(handler.mediaItem.value?.id, '/other.mp3');
    expect(handler.playbackState.value.queueIndex, isNull);
  });
}
