import 'package:flutter/foundation.dart';

/// Android MediaStore change detection.
///
/// This is intentionally small so it can be:
/// - implemented via native platform channels (ContentObserver / MediaStore.getVersion)
/// - replaced by fakes in unit tests
abstract class MediaStoreFreshness {
  /// True when MediaStore is known/suspected to have changed since last consume.
  ValueListenable<bool> get isDirty;

  /// Update internal state (if needed) and return whether MediaStore changed.
  ///
  /// If this returns true, implementations should also clear the dirty state
  /// (i.e. treat the change as consumed).
  Future<bool> consumeIfChanged();
}

/// Default implementation used when MediaStore freshness integration is disabled.
class NoopMediaStoreFreshness implements MediaStoreFreshness {
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get isDirty => _dirty;

  @override
  Future<bool> consumeIfChanged() async => false;
}


