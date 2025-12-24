import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playlist_store.dart';

void main() {
  late Directory tempDir;
  late PlaylistStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('playlist_store_test');
    store = PlaylistStore(
      hive: Hive,
      hiveInitializer: () async {
        Hive.init(tempDir.path);
      },
      boxOpener: (hive) => hive.openBox<dynamic>('playlistBox'),
    );
    await store.init();
  });

  tearDown(() async {
    await store.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('setQueue stores sequential order', () async {
    final tracks = List<AudioTrack>.generate(
      3,
      (i) => AudioTrack(path: 'path_$i', title: 'Track $i'),
    );

    await store.setQueue(tracks, startBaseIndex: 1);

    expect(store.queueNotifier.value.map((t) => t.title).toList(),
        ['Track 0', 'Track 1', 'Track 2']);
    expect(store.currentOrderIndexNotifier.value, 1);
    expect(store.shuffleNotifier.value, isFalse);
  });

  test('reshuffle keeps current track first', () async {
    final tracks = List<AudioTrack>.generate(
      6,
      (i) => AudioTrack(path: 'path_$i', title: 'Track $i'),
    );

    await store.setQueue(tracks, startBaseIndex: 3);
    final originalTitles =
        store.queueNotifier.value.map((t) => t.title).toList(growable: false);

    await store.reshuffle(keepBaseIndex: 3);
    var shuffledTitles =
        store.queueNotifier.value.map((t) => t.title).toList(growable: false);

    if (listEquals(originalTitles, shuffledTitles)) {
      await store.reshuffle(keepBaseIndex: 3);
      shuffledTitles = store.queueNotifier.value
          .map((t) => t.title)
          .toList(growable: false);
    }

    expect(store.shuffleNotifier.value, isTrue);
    expect(shuffledTitles.first, 'Track 3');
    expect(listEquals(originalTitles, shuffledTitles), isFalse);
  });

  test('restores persisted queue and shuffle order', () async {
    final tracks = List<AudioTrack>.generate(
      4,
      (i) => AudioTrack(path: 'path_$i', title: 'Track $i'),
    );

    await store.setQueue(tracks, startBaseIndex: 2, enableShuffle: true);
    final firstTitle = store.queueNotifier.value.first.title;

    await store.dispose();

    store = PlaylistStore(
      hive: Hive,
      hiveInitializer: () async {
        Hive.init(tempDir.path);
      },
      boxOpener: (hive) => hive.openBox<dynamic>('playlistBox'),
    );
    await store.init();

    expect(store.queueNotifier.value.length, tracks.length);
    expect(store.shuffleNotifier.value, isTrue);
    expect(store.queueNotifier.value.first.title, firstTitle);
    expect(store.currentOrderIndexNotifier.value, 0);
  });
}
