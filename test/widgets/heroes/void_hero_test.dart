import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/song_info.dart';
import 'package:nothingness/theme/app_typography.dart';
import 'package:nothingness/widgets/heroes/void_hero.dart';

import '_test_helpers.dart';

void main() {
  testWidgets('falls back to "nothingness" idle text when no track', (
    tester,
  ) async {
    final provider = FakeAudioPlayerProvider();
    await tester.pumpWidget(wrapWithProvider(provider, const VoidHero()));
    expect(find.text('nothingness'), findsOneWidget);
  });

  testWidgets('renders the active track title when a song is playing', (
    tester,
  ) async {
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
    await tester.pumpWidget(wrapWithProvider(provider, const VoidHero()));
    await tester.pump();
    expect(find.text('Wake Up'), findsOneWidget);
    expect(find.text('Indie'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // B-035 — textScale on VoidScreenConfig scales the title typography
  // ---------------------------------------------------------------------------
  testWidgets('textScale=0.8 scales the title fontSize by 0.8x',
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

    await tester.pumpWidget(
      wrapWithProvider(
        provider,
        const VoidHero(config: VoidScreenConfig(textScale: 0.8)),
      ),
    );
    await tester.pump();

    final titleFinder = find.text('Wake Up');
    expect(titleFinder, findsOneWidget);

    final titleWidget = tester.widget<Text>(titleFinder);
    final BuildContext ctx = tester.element(find.byType(VoidHero));
    final typography = Theme.of(ctx).extension<AppTypography>()!;

    expect(
      titleWidget.style?.fontSize,
      closeTo(typography.heroSize * 0.8, 0.01),
    );
  });
}
