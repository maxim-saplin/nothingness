/// Where the transport strip (prev / play-pause / next + seek hairline)
/// is anchored inside the Void chrome.
///
/// - [bottom] (default): just above the crumb, below the browser.
/// - [top]: pinned to the top of the browser band, immediately below the
///   hero. Always at the same y regardless of how many files the folder
///   holds — the browser scrolls under it instead of pushing it around.
/// - [off]: hidden. Hero gestures + the seek hairline at the bottom
///   continue to work, but the icon strip is gone.
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
