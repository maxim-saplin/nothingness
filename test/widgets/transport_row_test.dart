import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/song_info.dart';
import 'package:nothingness/widgets/press_feedback.dart';
import 'package:nothingness/widgets/transport_row.dart';

import 'heroes/_test_helpers.dart';

class _RecordingAudioPlayerProvider extends FakeAudioPlayerProvider {
  _RecordingAudioPlayerProvider({required SongInfo songInfo})
      : super(songInfo: songInfo);

  final List<Duration> seeks = <Duration>[];

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }
}

void main() {
  SongInfo song({int position = 10000, int duration = 60000}) => SongInfo(
        track: const AudioTrack(path: '/x.wav', title: 'x'),
        isPlaying: true,
        position: position,
        duration: duration,
      );

  testWidgets('renders prev / play / next buttons by stable keys', (
    tester,
  ) async {
    final provider = FakeAudioPlayerProvider();
    await tester.pumpWidget(wrapWithProvider(provider, const TransportRow()));

    expect(find.byKey(TransportRow.prevKey), findsOneWidget);
    expect(find.byKey(TransportRow.playKey), findsOneWidget);
    expect(find.byKey(TransportRow.nextKey), findsOneWidget);
  });

  testWidgets('play glyph flips to pause when isPlaying changes', (
    tester,
  ) async {
    final provider = FakeAudioPlayerProvider(isPlaying: false);
    await tester.pumpWidget(wrapWithProvider(provider, const TransportRow()));

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);

    provider.setIsPlaying(true);
    await tester.pump();

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  // B-012: touch-down on a transport button drops the icon's opacity for
  // immediate visual feedback; releasing restores it.
  testWidgets('play button dips on touch-down and restores on release', (
    tester,
  ) async {
    final provider = FakeAudioPlayerProvider(isPlaying: false);
    await tester.pumpWidget(wrapWithProvider(provider, const TransportRow()));

    final playFinder = find.byKey(TransportRow.playKey);
    expect(playFinder, findsOneWidget);

    final opacityFinder = find.descendant(
      of: playFinder,
      matching: find.byType(AnimatedOpacity),
    );
    expect(opacityFinder, findsOneWidget);

    // Idle
    AnimatedOpacity opacity = tester.widget<AnimatedOpacity>(opacityFinder);
    expect(opacity.opacity, 1.0);

    // Touch down (no release)
    final gesture = await tester.startGesture(tester.getCenter(playFinder));
    await tester.pump(const Duration(milliseconds: 16));
    opacity = tester.widget<AnimatedOpacity>(opacityFinder);
    expect(opacity.opacity, lessThan(1.0));

    // Release
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    opacity = tester.widget<AnimatedOpacity>(opacityFinder);
    expect(opacity.opacity, 1.0);
  });

  // B-030 follow-up: the transport row must use the universal
  // PressFeedback wrapper (0.4 dip, 120 ms / 200 ms fade), not the legacy
  // _TouchDownDimmer constants (0.45 / 80 ms). All three icon buttons
  // (prev / play / next) must be wrapped.
  testWidgets('transport buttons use PressFeedback with 0.4 pressed opacity',
      (tester) async {
    final provider = FakeAudioPlayerProvider(isPlaying: false);
    await tester.pumpWidget(wrapWithProvider(provider, const TransportRow()));

    for (final key in const [
      TransportRow.prevKey,
      TransportRow.playKey,
      TransportRow.nextKey,
    ]) {
      final btn = find.byKey(key);
      expect(btn, findsOneWidget);
      // The key is hoisted onto the PressFeedback itself (single source
      // of truth for press feedback — option (a)).
      expect(tester.widget(btn), isA<PressFeedback>(),
          reason: 'B-030 follow-up: $key must BE a PressFeedback widget.');
    }

    // Touch-down on play and assert the pressed opacity equals
    // PressFeedback.pressedOpacity (0.4), not the legacy 0.45.
    final playFinder = find.byKey(TransportRow.playKey);
    final opacityFinder = find.descendant(
      of: playFinder,
      matching: find.byType(AnimatedOpacity),
    );
    final gesture = await tester.startGesture(tester.getCenter(playFinder));
    await tester.pump(const Duration(milliseconds: 16));
    final opacity = tester.widget<AnimatedOpacity>(opacityFinder);
    expect(opacity.opacity, PressFeedback.pressedOpacity,
        reason: 'B-030 follow-up: transport press dip must match the '
            'universal PressFeedback.pressedOpacity (0.4), not the legacy '
            '_TouchDownDimmer 0.45.');
    expect(PressFeedback.pressedOpacity, 0.4,
        reason: 'Calibration constant must remain 0.4 per B-030.');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('seek strip tap commits one seek immediately on release', (
    tester,
  ) async {
    final provider = _RecordingAudioPlayerProvider(songInfo: song());
    await tester.pumpWidget(wrapWithProvider(provider, const TransportRow()));

    final seekFinder = find.byKey(TransportRow.seekKey);
    expect(seekFinder, findsOneWidget);

    await tester.tapAt(tester.getCenter(seekFinder));
    await tester.pump();

    expect(provider.seeks.length, 1);
    expect(provider.seeks.single.inSeconds, closeTo(30, 1));
  });

  testWidgets('seek strip drag previews but commits one seek on release', (
    tester,
  ) async {
    final provider = _RecordingAudioPlayerProvider(songInfo: song());
    await tester.pumpWidget(wrapWithProvider(provider, const TransportRow()));

    final seekFinder = find.byKey(TransportRow.seekKey);
    expect(seekFinder, findsOneWidget);

    final start = tester.getCenter(seekFinder);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();

    expect(provider.seeks, isEmpty,
        reason: 'dragging should preview locally without flooding seeks');

    await gesture.up();
    await tester.pump();

    expect(provider.seeks.length, 1,
        reason: 'drag should commit exactly once on release');
    expect(provider.seeks.single.inSeconds, greaterThan(20));
  });

  testWidgets('seek strip ignores gestures when duration is unavailable', (
    tester,
  ) async {
    final provider = _RecordingAudioPlayerProvider(songInfo: song(duration: 0));
    await tester.pumpWidget(wrapWithProvider(provider, const TransportRow()));

    final seekFinder = find.byKey(TransportRow.seekKey);
    expect(seekFinder, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(seekFinder));
    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pump();

    expect(provider.seeks, isEmpty);
  });
}
