import 'package:flutter/material.dart';

import '../../../models/screen_config.dart';
import 'cassette_image_variant.dart';
import 'cassette_shared.dart';
import 'variant_7.dart';

/// Single wiring file: maps each [CassetteVariant] to its builder.
/// v1/v2/v3/v5 use the supplied high-fidelity cassette layers; v4 is minimal.
final Map<CassetteVariant, Widget Function(CassetteVariantContext)>
cassetteVariantBuilders = {
  CassetteVariant.v1: (ctx) =>
      CassetteImageVariant(ctx, look: CassetteLook.mono),
  CassetteVariant.v2: (ctx) =>
      CassetteImageVariant(ctx, look: CassetteLook.copper),
  CassetteVariant.v3: (ctx) =>
      CassetteImageVariant(ctx, look: CassetteLook.nightwave),
  CassetteVariant.v4: (ctx) => CassetteVariant7(ctx),
  CassetteVariant.v5: (ctx) =>
      CassetteImageVariant(ctx, look: CassetteLook.poolside),
};
