/// Identifier for a registered theme.
///
/// `void` is a reserved word in Dart, hence the trailing underscore.
enum ThemeId {
  void_;

  /// Stable string used for persistence.
  String get storageKey {
    switch (this) {
      case ThemeId.void_:
        return 'void';
    }
  }

  static ThemeId fromStorageKey(String? key) {
    switch (key) {
      case 'void':
        return ThemeId.void_;
      default:
        return ThemeId.void_;
    }
  }
}
