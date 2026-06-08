import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/screen_config.dart';
import '../../../services/playback_controller.dart';
import '../base_hero_container.dart';
import 'cassette_registry.dart';
import 'cassette_shared.dart';

/// Hero slot widget for the cassette screen. Reads [PlaybackController] via
/// Provider, assembles a [CassetteVariantContext], and delegates to the
/// variant builder from [cassetteVariantBuilders].
class CassetteHero extends StatelessWidget {
  const CassetteHero({super.key, required this.config});

  final CassetteScreenConfig config;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlaybackController>();
    final info = context.select<PlaybackController, ({String? title, String? artist, int positionMs, int durationMs})>(
      (playback) => (
        title: playback.songInfo?.title,
        artist: playback.songInfo?.artist,
        positionMs: playback.songInfo?.position ?? 0,
        durationMs: playback.songInfo?.duration ?? 0,
      ),
    );
    final isPlaying =
        context.select<PlaybackController, bool>((playback) => playback.isPlaying);

    final ctx = CassetteVariantContext(
      config: config,
      title: info.title,
      artist: info.artist,
      isPlaying: isPlaying,
      positionMs: info.positionMs,
      durationMs: info.durationMs,
      onPlayPause: player.playPause,
      onPrevious: player.previous,
      onNext: player.next,
      onSeek: player.seek,
      spectrumListenable: config.usesVisualizer ? player.spectrumListenable : null,
      haptics: CassetteHaptics(enabled: config.hapticsEnabled),
    );

    final builder = cassetteVariantBuilders[config.variant] ??
        cassetteVariantBuilders[CassetteVariant.v1]!;

    return BaseHeroContainer(
      alignment: Alignment.center,
      child: builder(ctx),
    );
  }
}
