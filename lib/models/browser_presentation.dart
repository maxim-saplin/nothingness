/// Whether the library browser is permanently anchored to its slot [fixed]
/// (default), or hidden until revealed with a [swipeUp] gesture.
enum BrowserPresentation {
  fixed,
  swipeUp,
}

extension BrowserPresentationX on BrowserPresentation {
  String get storageKey {
    switch (this) {
      case BrowserPresentation.fixed:
        return 'fixed';
      case BrowserPresentation.swipeUp:
        return 'swipe_up';
    }
  }

  String get label {
    switch (this) {
      case BrowserPresentation.fixed:
        return 'fixed';
      case BrowserPresentation.swipeUp:
        return 'swipe up';
    }
  }

  static BrowserPresentation fromStorageKey(String? key) {
    switch (key) {
      case 'swipe_up':
        return BrowserPresentation.swipeUp;
      case 'fixed':
      default:
        return BrowserPresentation.fixed;
    }
  }
}
