import 'package:flutter/material.dart';

import '../app_palette.dart';

/// Void — dark variant. White on black at stepped opacities; `inverted` is the
/// near-white block behind the playing row (text inverts to black). `accent`
/// equals fgPrimary — Void has no chromatic accent but consumers expect a value.
const AppPalette voidPaletteDark = AppPalette(
  background: Color(0xFF000000),
  fgPrimary: Color(0xEBFFFFFF),
  fgSecondary: Color(0xD9FFFFFF),
  fgTertiary: Color(0x99FFFFFF),
  fgQuaternary: Color(0x66FFFFFF),
  divider: Color(0x0FFFFFFF),
  inverted: Color(0xEBFFFFFF),
  accent: Color(0xFFFFFFFF),
  progress: Color(0xFFFFFFFF),
);
