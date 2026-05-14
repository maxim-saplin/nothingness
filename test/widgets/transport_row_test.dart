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
}
