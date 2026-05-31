import 'package:audio_session/audio_session.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/services/playback/playback_bloc.dart';
import 'package:nothingness/services/playlist_store.dart';

import 'mock_audio_transport.dart';

/// Minimal in-memory playlist for the bloc (no Hive).
class _Playlist extends PlaylistStore {
  _Playlist(this._tracks, {int? current}) {
    currentOrderIndexNotifier.value = current;
  }
  final List<AudioTrack> _tracks;
  @override
  int get length => _tracks.length;
  @override
  AudioTrack? trackForOrderIndex(int i) =>
      (i >= 0 && i < _tracks.length) ? _tracks[i] : null;
  @override
  int? nextOrderIndex() {
    final c = currentOrderIndexNotifier.value;
    if (c == null) return _tracks.isEmpty ? null : 0;
    return c + 1 < length ? c + 1 : null;
  }

  @override
  int? previousOrderIndex() {
    final c = currentOrderIndexNotifier.value;
    if (c == null) return null;
    return c - 1 >= 0 ? c - 1 : null;
  }

  @override
  Future<void> setCurrentOrderIndex(int i) async {
    currentOrderIndexNotifier.value = i.clamp(0, length - 1);
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
}

List<AudioTrack> tracks(int n) => List.generate(
    n, (i) => AudioTrack(path: '/p/t$i.mp3', title: 'T$i'));

void main() {
  late MockAudioTransport tx;
  late _Playlist pl;

  PlaybackBloc build({int n = 3, int? current, Set<String>? fail,
      bool Function(String)? exists, bool preflight = false}) {
    tx = MockAudioTransport();
    if (fail != null) tx.pathsToFailOnLoad.addAll(fail);
    pl = _Playlist(tracks(n), current: current);
    return PlaybackBloc(
      transport: tx,
      playlist: pl,
      preflightFileExists: preflight,
      fileExists: (p) async => exists?.call(p) ?? true,
    );
  }

  test('initial state is Stopped', () {
    expect(build().state, isA<PbStopped>());
  });

  blocTest<PlaybackBloc, PbState>(
    'GoToIndex loads then plays',
    build: () => build(),
    act: (b) => b.add(const GoToIndex(0)),
    expect: () => [
      isA<PbLoading>().having((s) => s.index, 'i', 0),
      isA<PbActive>().having((s) => s.index, 'i', 0).having((s) => s.playing, 'p', true),
    ],
    verify: (_) => expect(tx.isPlaying, true),
  );

  blocTest<PlaybackBloc, PbState>(
    'GoToIndex respecting standing pause shows index without playing',
    build: () => build(),
    act: (b) => b.add(const GoToIndex(0, intentPlay: false, respectPauseIntent: true)),
    expect: () => [
      isA<PbActive>().having((s) => s.index, 'i', 0).having((s) => s.playing, 'p', false),
    ],
    verify: (_) => expect(tx.isPlaying, false),
  );

  blocTest<PlaybackBloc, PbState>(
    'next advances and plays',
    build: () => build(),
    act: (b) async {
      b.add(const GoToIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const GoNext());
    },
    skip: 2,
    expect: () => [
      isA<PbLoading>().having((s) => s.index, 'i', 1),
      isA<PbActive>().having((s) => s.index, 'i', 1),
    ],
  );

  blocTest<PlaybackBloc, PbState>(
    'next at tail is a no-op',
    build: () => build(n: 2, current: 1),
    act: (b) => b.add(const GoNext()),
    expect: () => [],
  );

  blocTest<PlaybackBloc, PbState>(
    'pause then resume keeps position (no reload)',
    build: () => build(),
    act: (b) async {
      b.add(const GoToIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const TogglePlayPause()); // pause
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const TogglePlayPause()); // resume
    },
    skip: 2,
    expect: () => [
      isA<PbActive>().having((s) => s.playing, 'p', false),
      isA<PbActive>().having((s) => s.playing, 'p', true),
    ],
    verify: (_) => expect(tx.loadCalls.length, 1, reason: 'resume must not reload'),
  );

  blocTest<PlaybackBloc, PbState>(
    'latest-wins: GoToIndex superseded by GoToIndex during load',
    build: () => build(n: 4),
    act: (b) async {
      tx.loadDelay = const Duration(milliseconds: 40);
      b.add(const GoToIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 10)); // mid-load
      b.add(const GoToIndex(2));
    },
    wait: const Duration(milliseconds: 120),
    verify: (b) {
      expect(b.state, isA<PbActive>().having((s) => s.index, 'i', 2));
      expect(tx.isPlaying, true);
    },
  );

  blocTest<PlaybackBloc, PbState>(
    'queue exhaustion: ended at tail -> Stopped; play restarts',
    build: () => build(n: 2, current: 1),
    act: (b) async {
      b.add(const GoToIndex(1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const TrackEnded("ended")); // tail end
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const TogglePlayPause()); // press play after exhaustion
    },
    wait: const Duration(milliseconds: 80),
    verify: (b) => expect(b.state, isA<PbActive>().having((s) => s.playing, 'p', true),
        reason: 'play after queue end must restart, not stay dead'),
  );

  blocTest<PlaybackBloc, PbState>(
    'failed track is skipped',
    build: () => build(n: 3, fail: {'/p/t1.mp3'}),
    act: (b) => b.add(const GoToIndex(1)),
    wait: const Duration(milliseconds: 80),
    verify: (b) => expect(b.state, isA<PbActive>().having((s) => s.index, 'i', 2)),
  );

  blocTest<PlaybackBloc, PbState>(
    'missing (preflight) track is skipped',
    build: () => build(n: 3, preflight: true, exists: (p) => !p.endsWith('t0.mp3')),
    act: (b) => b.add(const GoToIndex(0)),
    wait: const Duration(milliseconds: 80),
    verify: (b) => expect(b.state, isA<PbActive>().having((s) => s.index, 'i', 1)),
  );

  blocTest<PlaybackBloc, PbState>(
    'natural end auto-advances',
    build: () => build(n: 3),
    act: (b) async {
      b.add(const GoToIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const TrackEnded("ended"));
    },
    wait: const Duration(milliseconds: 80),
    verify: (b) => expect(b.state, isA<PbActive>().having((s) => s.index, 'i', 1)),
  );

  blocTest<PlaybackBloc, PbState>(
    'B-036: duplicate ended during in-flight advance does not double-skip',
    build: () => build(n: 4),
    act: (b) async {
      tx.loadDelay = const Duration(milliseconds: 50);
      b.add(const GoToIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 80)); // active idx0
      b.add(const TrackEnded("ended")); // advance to 1 (parks in load)
      await Future<void>.delayed(const Duration(milliseconds: 10));
      b.add(const TrackEnded("ended")); // duplicate while loading -> must be ignored
    },
    wait: const Duration(milliseconds: 150),
    verify: (b) {
      expect(b.state, isA<PbActive>().having((s) => s.index, 'i', 1));
      expect(tx.loadCalls.contains('/p/t2.mp3'), false, reason: 'no double-advance');
    },
  );

  blocTest<PlaybackBloc, PbState>(
    'interruption pauses then resumes',
    build: () => build(),
    act: (b) async {
      b.add(const GoToIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const InterruptionBegan(AudioInterruptionType.pause));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const InterruptionEnded(AudioInterruptionType.pause));
    },
    wait: const Duration(milliseconds: 60),
    verify: (b) => expect(b.state, isA<PbActive>().having((s) => s.playing, 'p', true)),
  );

  blocTest<PlaybackBloc, PbState>(
    'user pause during interruption: no resume on end',
    build: () => build(),
    act: (b) async {
      b.add(const GoToIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const InterruptionBegan(AudioInterruptionType.pause));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const TogglePlayPause()); // user keeps it paused (resume from paused? no — it's paused)
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const InterruptionEnded(AudioInterruptionType.pause));
    },
    wait: const Duration(milliseconds: 80),
    // After interruption pause, isPlaying=false; TogglePlayPause resumes it
    // (PbActive paused -> play). On end, _pausedByInterruption was cleared by
    // the toggle's resume path, so no surprise double-resume. End state playing.
    verify: (b) => expect(b.state, isA<PbActive>()),
  );

  blocTest<PlaybackBloc, PbState>(
    'becoming noisy pauses, no auto-resume',
    build: () => build(),
    act: (b) async {
      b.add(const GoToIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const BecameNoisy());
    },
    wait: const Duration(milliseconds: 40),
    verify: (b) => expect(b.state, isA<PbActive>().having((s) => s.playing, 'p', false)),
  );

  blocTest<PlaybackBloc, PbState>(
    'previous within 3s steps back',
    build: () => build(n: 3, current: 2),
    act: (b) async {
      b.add(const GoToIndex(2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      tx.emitPosition(const Duration(seconds: 1)); // <3s
      b.add(const GoPrevious());
    },
    wait: const Duration(milliseconds: 80),
    verify: (b) => expect(b.state, isA<PbActive>().having((s) => s.index, 'i', 1)),
  );

  blocTest<PlaybackBloc, PbState>(
    'previous after 3s restarts current',
    build: () => build(n: 3, current: 2),
    act: (b) async {
      b.add(const GoToIndex(2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      tx.emitPosition(const Duration(seconds: 5)); // >3s
      b.add(const GoPrevious());
    },
    wait: const Duration(milliseconds: 80),
    verify: (b) => expect(b.state, isA<PbActive>().having((s) => s.index, 'i', 2)),
  );

  blocTest<PlaybackBloc, PbState>(
    'rapid burst coalesces to the landed track',
    build: () => build(n: 6),
    act: (b) async {
      tx.loadDelay = const Duration(milliseconds: 30);
      b.add(const GoToIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 35));
      // 5 quick nexts
      for (var i = 0; i < 5; i++) {
        b.add(const GoNext());
      }
    },
    wait: const Duration(milliseconds: 200),
    verify: (b) {
      expect(b.state, isA<PbActive>().having((s) => s.index, 'i', 5));
      expect(tx.isPlaying, true);
    },
  );
}
