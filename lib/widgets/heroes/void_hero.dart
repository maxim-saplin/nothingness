import 'package:flutter/material.dart';

import '../../models/screen_config.dart';
import 'base_hero_container.dart';
import 'hero_title_block.dart';

/// Track-metadata hero for the `void` visualisation — the shared
/// [HeroTitleBlock] (Artist over Song) inside the void chrome. Spectrum and Dot
/// reuse the same block.
class VoidHero extends StatelessWidget {
  const VoidHero({super.key, this.config = const VoidScreenConfig()});

  final VoidScreenConfig config;

  @override
  Widget build(BuildContext context) {
    return BaseHeroContainer(
      width: double.infinity,
      // HeroTitleBlock owns the horizontal inset that keeps the title clear of
      // the top-right `⋮` settings button.
      padding: const EdgeInsets.symmetric(vertical: 12),
      showDivider: true,
      alignment: Alignment.center,
      child: HeroTitleBlock(textScale: config.textScale, showIdleHint: true),
    );
  }
}
