import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/widgets/transport_row.dart';

import 'heroes/_test_helpers.dart';

void main() {
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
}
