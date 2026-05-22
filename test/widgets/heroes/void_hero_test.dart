import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/song_info.dart';
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
}
