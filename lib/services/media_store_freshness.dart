import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform_channels.dart';

/// Android MediaStore change detection. Intentionally small: implemented via
/// native channels (ContentObserver / MediaStore.getVersion) or faked in tests.
abstract class MediaStoreFreshness {
  /// True when MediaStore is known/suspected to have changed since last consume.
  ValueListenable<bool> get isDirty;

  /// Update internal state and return whether MediaStore changed; a true result
  /// also clears the dirty state (treats the change as consumed).
  Future<bool> consumeIfChanged();
}

/// Default no-op used when MediaStore freshness integration is disabled.
class NoopMediaStoreFreshness implements MediaStoreFreshness {
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get isDirty => _dirty;

  @override
  Future<bool> consumeIfChanged() async => false;
}

/// Android impl backed by MediaStore ContentObserver (event stream) and
/// MediaStore.getVersion() (Android 11+).
class AndroidMediaStoreFreshness implements MediaStoreFreshness {
  AndroidMediaStoreFreshness({PlatformChannels? platformChannels})
      : _platformChannels = platformChannels ?? PlatformChannels() {
    if (Platform.isAndroid) {
      _sub = _platformChannels.mediaStoreChanges().listen((_) {
        _dirty.value = true;
      });
    }
  }

  final PlatformChannels _platformChannels;
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);

  StreamSubscription<void>? _sub;
  String? _lastVersion;

  @override
  ValueListenable<bool> get isDirty => _dirty;

  @override
  Future<bool> consumeIfChanged() async {
    if (!Platform.isAndroid) return false;

    // If observer already flagged dirty, consume immediately.
    if (_dirty.value) {
      _dirty.value = false;
      return true;
    }

    // Otherwise low-cost version comparison (Android 11+).
    final current = await _platformChannels.getMediaStoreVersion();
    if (current == null) return false;

    if (_lastVersion == null) {
      _lastVersion = current;
      return false;
    }

    if (current != _lastVersion) {
      _lastVersion = current;
      return true;
    }

    return false;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
