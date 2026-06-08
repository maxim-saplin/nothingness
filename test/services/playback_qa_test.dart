import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';

import '../support/pump_until.dart';
import 'mock_audio_transport.dart';

class _MockPlaylistStore extends PlaylistStore {
  final List<AudioTrack> _tracks = [];
  int? _currentIndex;

  @override
  int get length => _tracks.length;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startBaseIndex = 0,
    bool enableShuffle = false,
  }) async {
    _tracks
      ..clear()
      ..addAll(tracks);
    _currentIndex = startBaseIndex;
    queueNotifier.value = List<AudioTrack>.from(_tracks);
    currentOrderIndexNotifier.value = _currentIndex;
  }

  @override
  Future<void> setCurrentOrderIndex(int orderIndex) async {
    _currentIndex = orderIndex;
    currentOrderIndexNotifier.value = orderIndex;
  }

  @override
  AudioTrack? trackForOrderIndex(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= _tracks.length) return null;
    return _tracks[orderIndex];
  }

  @override
  int? nextOrderIndex() {
    final currentIndex = _currentIndex;
    if (currentIndex == null) return null;
    final nextIndex = currentIndex + 1;
    return nextIndex < _tracks.length ? nextIndex : null;
  }

  @override
  int? previousOrderIndex() {
    final currentIndex = _currentIndex;
    if (currentIndex == null) return null;
    final previousIndex = currentIndex - 1;
    return previousIndex >= 0 ? previousIndex : null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<AudioTrack> createTracks(int count) => List.generate(
      count, (i) => AudioTrack(path: '/path/track_$i.mp3', title: 't$i'));

  late MockAudioTransport transport;
  late PlaybackController controller;

  setUp(() async {
    transport = MockAudioTransport();
    controller = PlaybackController(
      transport: transport,
      playlist: _MockPlaylistStore(),
    );
    await controller.init();
  });

  tearDown(() async {
    await controller.shutdown();
  });

  test('QA: 50ms next bursts still coalesce to one landed load', () async {
    final tracks = createTracks(6);
    transport.loadDelay = const Duration(milliseconds: 10);
    await controller.setQueue(tracks);
    await pumpUntil(() => controller.currentIndexNotifier.value == 0);

    transport.loadCalls.clear();

    controller.next();
    await Future.delayed(const Duration(milliseconds: 50));
    controller.next();
    await Future.delayed(const Duration(milliseconds: 50));
    controller.next();
    await Future.delayed(const Duration(milliseconds: 50));
    controller.next();
    await Future.delayed(const Duration(milliseconds: 50));
    await controller.next();

    await pumpUntil(() =>
        controller.currentIndexNotifier.value == 5 &&
        controller.isPlayingNotifier.value);

    expect(controller.currentIndexNotifier.value, 5);
    expect(transport.loadCalls, ['/path/track_5.mp3']);
  });

  test('QA: 150ms next bursts load each stepped track in order', () async {
    final tracks = createTracks(6);
    transport.loadDelay = const Duration(milliseconds: 10);
    await controller.setQueue(tracks);
    await pumpUntil(() => controller.currentIndexNotifier.value == 0);

    transport.loadCalls.clear();

    controller.next();
    await Future.delayed(const Duration(milliseconds: 150));
    controller.next();
    await Future.delayed(const Duration(milliseconds: 150));
    controller.next();
    await Future.delayed(const Duration(milliseconds: 150));
    controller.next();
    await Future.delayed(const Duration(milliseconds: 150));
    await controller.next();

    await pumpUntil(() =>
        controller.currentIndexNotifier.value == 5 &&
        controller.isPlayingNotifier.value);

    expect(controller.currentIndexNotifier.value, 5);
    expect(
      transport.loadCalls,
      [
        '/path/track_1.mp3',
        '/path/track_2.mp3',
        '/path/track_3.mp3',
        '/path/track_4.mp3',
        '/path/track_5.mp3',
      ],
    );
  });

  test('QA: next during an in-flight load suppresses stale play', () async {
    final tracks = createTracks(6);
    transport.loadDelay = const Duration(milliseconds: 200);
    await controller.setQueue(tracks);
    await pumpUntil(() => controller.currentIndexNotifier.value == 0);

    transport.loadCalls.clear();
    transport.playCalls.clear();

    controller.next();
    await Future.delayed(const Duration(milliseconds: 150));
    controller.next();
    await pumpUntil(() => transport.playCalls.contains('/path/track_2.mp3'));

    expect(controller.currentIndexNotifier.value, 2);
    expect(transport.loadCalls, ['/path/track_1.mp3', '/path/track_2.mp3']);
    expect(transport.playCalls, ['/path/track_2.mp3']);
    expect(transport.loadedPath, '/path/track_2.mp3');
  });
}
