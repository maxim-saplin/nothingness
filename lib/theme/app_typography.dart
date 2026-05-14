import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Typography tokens consumed by themed surfaces.
class AppTypography extends ThemeExtension<AppTypography> {
  final String monoFamily;
  final double heroSize;
  final double rowSize;
  final double crumbSize;
  final double hintSize;
  final double heroLetterSpacing;
  final double rowLetterSpacing;

  const AppTypography({
    required this.monoFamily,
    required this.heroSize,
    required this.rowSize,
    required this.crumbSize,
    required this.hintSize,
    required this.heroLetterSpacing,
    required this.rowLetterSpacing,
  });

  @override
  AppTypography copyWith({
    String? monoFamily,
    double? heroSize,
    double? rowSize,
    double? crumbSize,
    double? hintSize,
    double? heroLetterSpacing,
    double? rowLetterSpacing,
  }) {
    return AppTypography(
      monoFamily: monoFamily ?? this.monoFamily,
      heroSize: heroSize ?? this.heroSize,
      rowSize: rowSize ?? this.rowSize,
      crumbSize: crumbSize ?? this.crumbSize,
      hintSize: hintSize ?? this.hintSize,
      heroLetterSpacing: heroLetterSpacing ?? this.heroLetterSpacing,
      rowLetterSpacing: rowLetterSpacing ?? this.rowLetterSpacing,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      monoFamily: t < 0.5 ? monoFamily : other.monoFamily,
      heroSize: lerpDouble(heroSize, other.heroSize, t) ?? heroSize,
      rowSize: lerpDouble(rowSize, other.rowSize, t) ?? rowSize,
      crumbSize: lerpDouble(crumbSize, other.crumbSize, t) ?? crumbSize,
      hintSize: lerpDouble(hintSize, other.hintSize, t) ?? hintSize,
      heroLetterSpacing:
          lerpDouble(heroLetterSpacing, other.heroLetterSpacing, t) ??
              heroLetterSpacing,
      rowLetterSpacing:
          lerpDouble(rowLetterSpacing, other.rowLetterSpacing, t) ??
              rowLetterSpacing,
    );
  }
}
