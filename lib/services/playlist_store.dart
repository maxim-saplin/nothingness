import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';

/// Manages the playback queue and shuffle order.
class PlaylistStore {
  final ValueNotifier<List<AudioTrack>> queueNotifier =
      ValueNotifier<List<AudioTrack>>(<AudioTrack>[]);
  final ValueNotifier<int?> currentOrderIndexNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<bool> shuffleNotifier = ValueNotifier<bool>(false);

  List<AudioTrack> _baseQueue = <AudioTrack>[];
  List<int> _order = <int>[];
  bool _shuffleEnabled = false;

  int get length => _order.length;
  int get baseLength => _baseQueue.length;

  int? get currentBaseIndex {
    final orderIndex = currentOrderIndexNotifier.value;
    if (orderIndex == null || orderIndex < 0 || orderIndex >= _order.length) {
      return null;
    }
    return _order[orderIndex];
  }

  Future<void> init() async {}

  Future<void> dispose() async {
    queueNotifier.dispose();
    currentOrderIndexNotifier.dispose();
    shuffleNotifier.dispose();
  }

  List<AudioTrack> get _orderedQueue =>
      _order.map((index) => _baseQueue[index]).toList(growable: false);

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startBaseIndex = 0,
    bool enableShuffle = false,
  }) async {
    _baseQueue = List<AudioTrack>.from(tracks);
    _shuffleEnabled = enableShuffle;
    shuffleNotifier.value = enableShuffle;
    _rebuildOrder(keepBaseIndex: startBaseIndex);
    queueNotifier.value = _orderedQueue;
    await setCurrentBaseIndex(startBaseIndex);
  }

  Future<void> addTracks(List<AudioTrack> tracks) async {
    final startIndex = _baseQueue.length;
    _baseQueue.addAll(tracks);
    for (int i = 0; i < tracks.length; i++) {
      _order.add(startIndex + i);
    }
    queueNotifier.value = _orderedQueue;
  }

  Future<void> setCurrentOrderIndex(int orderIndex) async {
    if (orderIndex < 0 || orderIndex >= _order.length) return;
    currentOrderIndexNotifier.value = orderIndex;
  }

  Future<void> setCurrentBaseIndex(int baseIndex) async {
    final orderIndex = orderIndexForBase(baseIndex) ?? baseIndex;
    await setCurrentOrderIndex(orderIndex);
  }

  AudioTrack? trackForOrderIndex(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= _order.length) return null;
    final baseIndex = _order[orderIndex];
    if (baseIndex < 0 || baseIndex >= _baseQueue.length) return null;
    return _baseQueue[baseIndex];
  }

  int? nextOrderIndex() {
    final current = currentOrderIndexNotifier.value;
    if (current == null) return null;
    final next = current + 1;
    return next < _order.length ? next : null;
  }

  int? previousOrderIndex() {
    final current = currentOrderIndexNotifier.value;
    if (current == null) return null;
    final prev = current - 1;
    return prev >= 0 ? prev : null;
  }

  int? orderIndexForBase(int baseIndex) {
    final idx = _order.indexOf(baseIndex);
    return idx >= 0 ? idx : null;
  }

  Future<void> reshuffle({required int keepBaseIndex}) async {
    _shuffleEnabled = true;
    shuffleNotifier.value = true;
    _rebuildOrder(keepBaseIndex: keepBaseIndex);
    queueNotifier.value = _orderedQueue;
    await setCurrentBaseIndex(keepBaseIndex);
  }

  Future<void> disableShuffle({required int keepBaseIndex}) async {
    _shuffleEnabled = false;
    shuffleNotifier.value = false;
    _rebuildOrder(keepBaseIndex: keepBaseIndex, forceSequential: true);
    queueNotifier.value = _orderedQueue;
    await setCurrentBaseIndex(keepBaseIndex);
  }

  int? orderIndexOfCurrent() => currentOrderIndexNotifier.value;

  Future<int> persistentSizeBytes() async {
    // No persistence implemented; return approximate in-memory size.
    return _baseQueue.length * 128;
  }

  void _rebuildOrder({int? keepBaseIndex, bool forceSequential = false}) {
    final indices = List<int>.generate(_baseQueue.length, (i) => i);
    if (_shuffleEnabled && !forceSequential) {
      indices.shuffle(Random());
      if (keepBaseIndex != null && indices.contains(keepBaseIndex)) {
        indices.remove(keepBaseIndex);
        indices.insert(0, keepBaseIndex);
      }
    }
    _order = indices;
  }
}
