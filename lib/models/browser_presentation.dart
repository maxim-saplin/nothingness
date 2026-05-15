/// Whether the library browser is permanently anchored to its slot, or
/// hidden until the user reveals it with a swipe-up.
///
/// - [fixed] (default): the browser always occupies its slot between the
///   hero and the crumb (modulo transport position).
/// - [swipeUp]: the slot is empty by default — a single "↑ swipe to
///   browse" hint sits at the bottom. An upward drag on the empty area
///   slides the browser in; Android Back, or the new `<` hint, collapses
///   it again.
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
