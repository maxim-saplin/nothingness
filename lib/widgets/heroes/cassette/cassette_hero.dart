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
    final player = context.watch<PlaybackController>();
    final info = player.songInfo;

    final ctx = CassetteVariantContext(
      config: config,
      title: info?.title,
      artist: info?.artist,
      isPlaying: player.isPlaying,
      positionMs: info?.position ?? 0,
      durationMs: info?.duration ?? 0,
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
