import 'package:flutter/material.dart';

import '../models/theme_id.dart';
import 'app_geometry.dart';
import 'app_palette.dart';
import 'app_typography.dart';
import 'palettes/void_dark.dart';
import 'palettes/void_light.dart';

const AppTypography _voidTypography = AppTypography(
  monoFamily: 'monospace',
  heroSize: 30.0,
  rowSize: 14.0,
  crumbSize: 11.0,
  hintSize: 10.0,
  heroLetterSpacing: 0.0,
  rowLetterSpacing: 0.0,
);

const AppGeometry _voidGeometry = AppGeometry(
  rowHeight: 34.0,
  dividerThickness: 1.0,
  // Void doesn't snap a sheet — it pushes a route. 0 disables snap callers.
  sheetSnapHeight: 0.0,
  heroFraction: 0.32,
);

/// Resolve the [AppPalette] for the given theme + brightness.
AppPalette paletteFor(ThemeId id, Brightness brightness) {
  switch (id) {
    case ThemeId.void_:
      return brightness == Brightness.dark ? voidPaletteDark : voidPaletteLight;
  }
}

/// Build the [ThemeData] for the requested theme id at the given brightness.
ThemeData buildAppTheme({
  required ThemeId id,
  required Brightness brightness,
}) {
  switch (id) {
    case ThemeId.void_:
      return _buildVoidTheme(brightness);
  }
}

ThemeData _buildVoidTheme(Brightness brightness) {
  final palette = paletteFor(ThemeId.void_, brightness);

  final base = brightness == Brightness.dark
      ? ThemeData.dark()
      : ThemeData.light();

  final scheme = (brightness == Brightness.dark
          ? const ColorScheme.dark()
          : const ColorScheme.light())
      .copyWith(
    primary: palette.accent,
    surface: palette.background,
    onSurface: palette.fgPrimary,
  );

  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[
      palette,
      _voidTypography,
      _voidGeometry,
    ],
  );
}
