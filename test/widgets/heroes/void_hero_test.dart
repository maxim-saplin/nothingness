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

  // ---------------------------------------------------------------------------
  // B-040 — Artist (H1) + Song title (H2) hierarchy
  // ---------------------------------------------------------------------------
  testWidgets('renders Artist (H1) above Song title (H2) when a song plays', (
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

    // B-040: artist is now displayed (was never shown before); the parent
    // folder name ("Indie") is no longer used as the subtitle.
    expect(find.text('Arcade Fire'), findsOneWidget);
    expect(find.text('Wake Up'), findsOneWidget);
    expect(find.text('Indie'), findsNothing);

    final BuildContext ctx = tester.element(find.byType(VoidHero));
    final typography = Theme.of(ctx).extension<AppTypography>()!;

    final artist = tester.widget<Text>(
      find.byKey(const ValueKey('void-hero-artist')),
    );
    final song = tester.widget<Text>(
      find.byKey(const ValueKey('void-hero-song')),
    );
    // H1 (Artist) is the larger heading; H2 (Song) is songSizeFactor× smaller.
    expect(artist.style?.fontSize, closeTo(typography.heroSize, 0.01));
    expect(
      song.style?.fontSize,
      closeTo(typography.heroSize * VoidHero.songSizeFactor, 0.01),
    );
    expect(artist.style!.fontSize!, greaterThan(song.style!.fontSize!));
  });

  testWidgets('falls back to song title as H1 when artist is empty (B-040)', (
    tester,
  ) async {
    final provider = FakeAudioPlayerProvider(
      songInfo: const SongInfo(
        track: AudioTrack(
          path: '/sdcard/Music/Indie/untitled.mp3',
          title: 'untitled',
          // No parsed artist (filename had no "Artist - Title" separator).
          artist: '',
        ),
        isPlaying: true,
        position: 0,
        duration: 200000,
      ),
    );
    await tester.pumpWidget(wrapWithProvider(provider, const VoidHero()));
    await tester.pump();

    // No empty artist headline; the song takes the primary slot at H1 size.
    expect(find.byKey(const ValueKey('void-hero-artist')), findsNothing);
    final song = tester.widget<Text>(
      find.byKey(const ValueKey('void-hero-song')),
    );
    final BuildContext ctx = tester.element(find.byType(VoidHero));
    final typography = Theme.of(ctx).extension<AppTypography>()!;
    expect(song.style?.fontSize, closeTo(typography.heroSize, 0.01));
  });

  // ---------------------------------------------------------------------------
  // B-035 / B-040 — textScale scales BOTH heading levels
  // ---------------------------------------------------------------------------
  testWidgets('textScale=0.8 scales both Artist and Song fontSize by 0.8x',
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

    final BuildContext ctx = tester.element(find.byType(VoidHero));
    final typography = Theme.of(ctx).extension<AppTypography>()!;

    final artist = tester.widget<Text>(
      find.byKey(const ValueKey('void-hero-artist')),
    );
    final song = tester.widget<Text>(
      find.byKey(const ValueKey('void-hero-song')),
    );
    expect(artist.style?.fontSize, closeTo(typography.heroSize * 0.8, 0.01));
    expect(
      song.style?.fontSize,
      closeTo(typography.heroSize * VoidHero.songSizeFactor * 0.8, 0.01),
    );
  });
}
