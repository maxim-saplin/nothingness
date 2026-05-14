import 'package:flutter/material.dart';

/// Light / dark selection or platform follow.
enum ThemeVariant {
  dark,
  light,
  system;

  String get storageKey => name;

  static ThemeVariant fromStorageKey(String? key) {
    return ThemeVariant.values.firstWhere(
      (v) => v.name == key,
      orElse: () => ThemeVariant.system,
    );
  }

  ThemeMode get themeMode {
    switch (this) {
      case ThemeVariant.dark:
        return ThemeMode.dark;
      case ThemeVariant.light:
        return ThemeMode.light;
      case ThemeVariant.system:
        return ThemeMode.system;
    }
  }
}
