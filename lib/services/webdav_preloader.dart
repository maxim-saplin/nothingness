import 'dart:async';

import 'package:flutter/foundation.dart';

import 'playlist_store.dart';
import 'track_file_resolver.dart';

/// Keeps the upcoming remote queue entries pinned and downloads them in order.
class WebDavPreloader {
  WebDavPreloader({
    required PlaylistStore playlist,
    required TrackFileResolver resolver,
    required ValueListenable<int> count,
  }) : _playlist = playlist,
       _resolver = resolver,
       _count = count {
    _playlist.queueNotifier.addListener(_refresh);
    _playlist.currentOrderIndexNotifier.addListener(_refresh);
    _count.addListener(_refresh);
  }

  final PlaylistStore _playlist;
  final TrackFileResolver _resolver;
  final ValueListenable<int> _count;
  final Set<String> _wanted = {};
  final Set<String> _attempted = {};
  String? _activePath;
  bool _running = false;
  bool _disposed = false;

  void setActivePath(String? path) {
    _activePath = path;
    _refresh();
  }

  void _refresh() {
    if (_disposed) return;
    final index = _playlist.currentOrderIndexNotifier.value;
    final current = index == null ? null : _playlist.trackForOrderIndex(index);
    final next = <String>{};
    if (_activePath != null && current?.path == _activePath) {
      for (
        var i = index! + 1;
        i < _playlist.length && i <= index + _count.value;
        i++
      ) {
        final path = _playlist.trackForOrderIndex(i)?.path;
        if (path != null && path != _activePath && _resolver.supports(path)) {
          next.add(path);
        }
      }
    }
    for (final path in next.difference(_wanted)) {
      _resolver.pin(path);
    }
    for (final path in _wanted.difference(next)) {
      _resolver.unpin(path);
      _attempted.remove(path);
    }
    _wanted
      ..clear()
      ..addAll(next);
    if (!_running && _wanted.difference(_attempted).isNotEmpty) {
      _running = true;
      unawaited(_download());
    }
  }

  Future<void> _download() async {
    while (!_disposed) {
      final pending = _wanted.difference(_attempted);
      if (pending.isEmpty) break;
      final path = pending.first;
      _attempted.add(path);
      // An in-flight download needs its own pin if the queue changes.
      _resolver.pin(path);
      try {
        await _resolver.resolveLocalPath(path, preloading: true);
      } catch (error) {
        debugPrint('[WebDavPreloader] preload failed for $path: $error');
      } finally {
        _resolver.unpin(path);
      }
    }
    _running = false;
  }

  void dispose() {
    _disposed = true;
    _playlist.queueNotifier.removeListener(_refresh);
    _playlist.currentOrderIndexNotifier.removeListener(_refresh);
    _count.removeListener(_refresh);
    for (final path in _wanted) {
      _resolver.unpin(path);
    }
    _wanted.clear();
  }
}
