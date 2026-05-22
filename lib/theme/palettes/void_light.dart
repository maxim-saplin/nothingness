import 'package:flutter/material.dart';

import '../app_palette.dart';

/// Void — light variant.
///
/// Mirror of [voidPaletteDark]: black on white at the same alpha tiers. The
/// playing-row block in this variant is near-black, with row text inverting
/// to white — the playing row is always *opposed* to the current variant, a
/// deliberate Void signature.
const AppPalette voidPaletteLight = AppPalette(
  background: Color(0xFFFFFFFF),
  fgPrimary: Color(0xEB000000),
  fgSecondary: Color(0xD9000000),
  fgTertiary: Color(0x99000000),
  fgQuaternary: Color(0x66000000),
  divider: Color(0x0F000000),
  inverted: Color(0xEB000000),
  accent: Color(0xFF000000),
  progress: Color(0xFF000000),
);
