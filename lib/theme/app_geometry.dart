import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Geometry tokens consumed by themed surfaces.
class AppGeometry extends ThemeExtension<AppGeometry> {
  final double rowHeight;
  final double dividerThickness;
  final double sheetSnapHeight;
  final double heroFraction;

  const AppGeometry({
    required this.rowHeight,
    required this.dividerThickness,
    required this.sheetSnapHeight,
    required this.heroFraction,
  });

  @override
  AppGeometry copyWith({
    double? rowHeight,
    double? dividerThickness,
    double? sheetSnapHeight,
    double? heroFraction,
  }) {
    return AppGeometry(
      rowHeight: rowHeight ?? this.rowHeight,
      dividerThickness: dividerThickness ?? this.dividerThickness,
      sheetSnapHeight: sheetSnapHeight ?? this.sheetSnapHeight,
      heroFraction: heroFraction ?? this.heroFraction,
    );
  }

  @override
  AppGeometry lerp(ThemeExtension<AppGeometry>? other, double t) {
    if (other is! AppGeometry) return this;
    return AppGeometry(
      rowHeight: lerpDouble(rowHeight, other.rowHeight, t) ?? rowHeight,
      dividerThickness:
          lerpDouble(dividerThickness, other.dividerThickness, t) ??
              dividerThickness,
      sheetSnapHeight:
          lerpDouble(sheetSnapHeight, other.sheetSnapHeight, t) ??
              sheetSnapHeight,
      heroFraction:
          lerpDouble(heroFraction, other.heroFraction, t) ?? heroFraction,
    );
  }
}
