/// Where the transport strip is anchored inside the Void chrome: [bottom]
/// (above crumb, default), [top] (pinned below hero), or [off] (hidden).
enum TransportPosition {
  bottom,
  top,
  off,
}

extension TransportPositionX on TransportPosition {
  /// Persisted token (stable across app upgrades).
  String get storageKey {
    switch (this) {
      case TransportPosition.bottom:
        return 'bottom';
      case TransportPosition.top:
        return 'top';
      case TransportPosition.off:
        return 'off';
    }
  }

  /// Human label for the settings row.
  String get label => storageKey;

  static TransportPosition fromStorageKey(String? key) {
    switch (key) {
      case 'top':
        return TransportPosition.top;
      case 'off':
        return TransportPosition.off;
      case 'bottom':
      default:
        return TransportPosition.bottom;
    }
  }
}
