import 'package:flutter/material.dart';

import '../../../models/screen_config.dart';
import 'cassette_image_variant.dart';
import 'cassette_shared.dart';
import 'variant_7.dart';

/// Single wiring file: maps each [CassetteVariant] to its builder.
/// v1/v2/v3 are the asset-based cassette (mono / amber / colour); v4 is minimal.
final Map<CassetteVariant, Widget Function(CassetteVariantContext)>
    cassetteVariantBuilders = {
  CassetteVariant.v1: (ctx) =>
      CassetteImageVariant(ctx, scheme: CassetteScheme.mono),
  CassetteVariant.v2: (ctx) =>
      CassetteImageVariant(ctx, scheme: CassetteScheme.amber),
  CassetteVariant.v3: (ctx) =>
      CassetteImageVariant(ctx, scheme: CassetteScheme.colorful),
  CassetteVariant.v4: (ctx) => CassetteVariant7(ctx),
};
