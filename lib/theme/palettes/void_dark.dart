import 'package:flutter/material.dart';

import '../app_palette.dart';

/// Void — dark variant.
///
/// Alpha tiers mirror the v6_monk prototype: pure white on pure black with
/// stepped opacities for hierarchy. The "inverted" tier is the near-white
/// block painted behind the currently-playing row; row text on top of it
/// inverts to black. Accent is intentionally equal to fgPrimary — Void uses
/// no chromatic accent, but consumers still expect a non-null value.
const AppPalette voidPaletteDark = AppPalette(
  background: Color(0xFF000000),
  // v6_monk: row default 0.85, hero title 0.92, fully bright 1.0. We collapse
  // these to a single fgPrimary at 0.92 (the hero/playing tier) and use
  // fgSecondary for body rows at 0.85.
  fgPrimary: Color(0xEBFFFFFF),
  fgSecondary: Color(0xD9FFFFFF),
  // .row.folder = 0.6; crumb tail = 0.55. Round to 0.6.
  fgTertiary: Color(0x99FFFFFF),
  // crumb default = 0.4; pre-hint glyph = 0.5; hint = 0.22. Pick 0.4 as the
  // workhorse tier; the launch hint dips down to fgQuaternary.
  fgQuaternary: Color(0x66FFFFFF),
  // .row::before / borders = 0.05-0.06. Round to 0.06.
  divider: Color(0x0FFFFFFF),
  // .row.playing background = 0.92. Inverted text becomes black via palette.background.
  inverted: Color(0xEBFFFFFF),
  accent: Color(0xFFFFFFFF),
  progress: Color(0xFFFFFFFF),
);
