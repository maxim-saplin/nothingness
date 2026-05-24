import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/song_info.dart';
import 'package:nothingness/widgets/heroes/dot_hero.dart';

import '_test_helpers.dart';

void main() {
  testWidgets('dot grows when bass energy is high', (tester) async {
    final provider = FakeAudioPlayerProvider(
      spectrumData: List<double>.filled(8, 0.0),
    );
    const config = DotScreenConfig();

    await tester.pumpWidget(
      wrapWithProvider(
        provider,
        const SizedBox(
          width: 400,
          height: 400,
          child: DotHero(config: config),
        ),
      ),
    );

    Size dotSizeFor(WidgetTester tester) {
      // The dot is the inner Container (last in the tree under the outer
      // background-coloured Container).
      final inner = find.descendant(
        of: find.byType(DotHero),
        matching: find.byType(Container),
      );
      // Outer fills, inner = circle. Pick the smaller one.
      final outerSize = tester.getSize(inner.first);
      final innerSize = tester.getSize(inner.last);
      return innerSize.width < outerSize.width ? innerSize : outerSize;
    }

    final smallSize = dotSizeFor(tester);

    provider.setSpectrum(List<double>.filled(8, 1.0));
    await tester.pump();

    final bigSize = dotSizeFor(tester);
    expect(bigSize.width, greaterThan(smallSize.width));
  });

  // ---------------------------------------------------------------------------
  // B-020 — toggleable song info overlay
  // ---------------------------------------------------------------------------

  testWidgets(
      'showSongInfo defaults to false — no title / parent folder in tree',
      (tester) async {
    final provider = FakeAudioPlayerProvider(
      songInfo: const SongInfo(
        track: AudioTrack(
          path: '/sdcard/Music/Indie/Wake Up.mp3',
          title: 'Wake Up',
          artist: 'Arcade Fire',
        ),
        isPlaying: true,
        position: 0,
        duration: 200000,
      ),
    );
    const config = DotScreenConfig();
    expect(config.showSongInfo, isFalse);

    await tester.pumpWidget(
      wrapWithProvider(
        provider,
        const SizedBox(
          width: 400,
          height: 400,
          child: DotHero(config: config),
        ),
      ),
    );

    // Default: minimalist identity — no title / parent overlay rendered.
    expect(find.text('Wake Up'), findsNothing);
    expect(find.text('Indie'), findsNothing);
  });

  testWidgets(
      'showSongInfo == true renders title + parent folder over the dot',
      (tester) async {
    final provider = FakeAudioPlayerProvider(
      songInfo: const SongInfo(
        track: AudioTrack(
          path: '/sdcard/Music/Indie/Wake Up.mp3',
          title: 'Wake Up',
          artist: 'Arcade Fire',
        ),
        isPlaying: true,
        position: 0,
        duration: 200000,
      ),
    );
    const config = DotScreenConfig(showSongInfo: true);

    await tester.pumpWidget(
      wrapWithProvider(
        provider,
        const SizedBox(
          width: 400,
          height: 400,
          child: DotHero(config: config),
        ),
      ),
    );

    expect(find.text('Wake Up'), findsOneWidget);
    expect(find.text('Indie'), findsOneWidget);
  });

  testWidgets(
      'showSongInfo == true with no track shows the idle "nothingness" label',
      (tester) async {
    final provider = FakeAudioPlayerProvider();
    const config = DotScreenConfig(showSongInfo: true);

    await tester.pumpWidget(
      wrapWithProvider(
        provider,
        const SizedBox(
          width: 400,
          height: 400,
          child: DotHero(config: config),
        ),
      ),
    );

    expect(find.text('nothingness'), findsOneWidget);
  });
}
