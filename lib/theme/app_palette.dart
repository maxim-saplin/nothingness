import 'package:flutter/material.dart';

/// Colour tokens consumed by themed surfaces.
///
/// `accent` is kept for theme parity even when a theme (e.g. Void) does not
/// use a chromatic accent — legacy screens still need a fallback colour.
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color fgPrimary;
  final Color fgSecondary;
  final Color fgTertiary;
  final Color fgQuaternary;
  final Color divider;
  final Color inverted;
  final Color accent;
  final Color progress;

  const AppPalette({
    required this.background,
    required this.fgPrimary,
    required this.fgSecondary,
    required this.fgTertiary,
    required this.fgQuaternary,
    required this.divider,
    required this.inverted,
    required this.accent,
    required this.progress,
  });

  @override
  AppPalette copyWith({
    Color? background,
    Color? fgPrimary,
    Color? fgSecondary,
    Color? fgTertiary,
    Color? fgQuaternary,
    Color? divider,
    Color? inverted,
    Color? accent,
    Color? progress,
  }) {
    return AppPalette(
      background: background ?? this.background,
      fgPrimary: fgPrimary ?? this.fgPrimary,
      fgSecondary: fgSecondary ?? this.fgSecondary,
      fgTertiary: fgTertiary ?? this.fgTertiary,
      fgQuaternary: fgQuaternary ?? this.fgQuaternary,
      divider: divider ?? this.divider,
      inverted: inverted ?? this.inverted,
      accent: accent ?? this.accent,
      progress: progress ?? this.progress,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t) ?? background,
      fgPrimary: Color.lerp(fgPrimary, other.fgPrimary, t) ?? fgPrimary,
      fgSecondary: Color.lerp(fgSecondary, other.fgSecondary, t) ?? fgSecondary,
      fgTertiary: Color.lerp(fgTertiary, other.fgTertiary, t) ?? fgTertiary,
      fgQuaternary:
          Color.lerp(fgQuaternary, other.fgQuaternary, t) ?? fgQuaternary,
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      inverted: Color.lerp(inverted, other.inverted, t) ?? inverted,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      progress: Color.lerp(progress, other.progress, t) ?? progress,
    );
  }
}
