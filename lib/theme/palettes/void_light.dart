import 'package:flutter/material.dart';

import '../app_palette.dart';

/// Void — light variant. Mirror of [voidPaletteDark]: black on white; the
/// playing row is near-black with text inverting to white (always opposed to
/// the variant, a deliberate Void signature).
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
