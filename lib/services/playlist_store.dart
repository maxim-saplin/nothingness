import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:nothingness/models/audio_track.dart';

/// Manages the playback queue, shuffle order, and persistence.
class PlaylistStore {
  PlaylistStore({
    HiveInterface? hive,
    Future<void> Function()? hiveInitializer,
    Future<Box<dynamic>> Function(HiveInterface)? boxOpener,
  })  : _hive = hive ?? Hive,
        _initHive = hiveInitializer ?? Hive.initFlutter,
        _openBox = boxOpener ?? ((hive) => hive.openBox<dynamic>(_boxName));

  static const String _boxName = 'playlistBox';
  static const String _queueKey = 'queue';
  static const String _orderKey = 'order';
  static const String _indexKey = 'currentIndex';
  static const String _shuffleKey = 'shuffle';

  final HiveInterface _hive;
  final Future<void> Function() _initHive;
  final Future<Box<dynamic>> Function(HiveInterface) _openBox;
  final Random _random = Random();

  final ValueNotifier<List<AudioTrack>> queueNotifier =
      ValueNotifier<List<AudioTrack>>(<AudioTrack>[]);
  final ValueNotifier<int?> currentOrderIndexNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<bool> shuffleNotifier = ValueNotifier<bool>(false);

  Box<dynamic>? _box;
  List<AudioTrack> _baseQueue = <AudioTrack>[];
  List<int> _playOrder = <int>[];

  int get length => _playOrder.length;
  int get baseLength => _baseQueue.length;

  int? get currentBaseIndex {
    final orderIndex = currentOrderIndexNotifier.value;
    if (orderIndex == null || orderIndex < 0 || orderIndex >= _playOrder.length) {
      return null;
    }
    return _playOrder[orderIndex];
  }

  Future<void> init() async {
    await _initHive();
    _box ??= await _openBox(_hive);
    await _restoreState();
  }

  Future<void> dispose() async {
    await _box?.flush();
    await _box?.close();
  }

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startBaseIndex = 0,
    bool enableShuffle = false,
  }) async {
    if (tracks.isEmpty) {
      _baseQueue = <AudioTrack>[];
      _playOrder = <int>[];
      currentOrderIndexNotifier.value = null;
      shuffleNotifier.value = false;
      queueNotifier.value = const [];
      await _persistState();
      return;
    }

    _baseQueue = List<AudioTrack>.unmodifiable(tracks);
    final baseIndex = _clampBaseIndex(startBaseIndex);
    shuffleNotifier.value = enableShuffle || shuffleNotifier.value;

    if (shuffleNotifier.value) {
      _playOrder = _buildShuffledOrder(startBaseIndex: baseIndex);
      currentOrderIndexNotifier.value = 0;
    } else {
      _playOrder = List<int>.generate(_baseQueue.length, (i) => i);
      currentOrderIndexNotifier.value = baseIndex;
    }

    _notifyQueue();
    await _persistState();
  }

  Future<void> addTracks(List<AudioTrack> tracks) async {
    if (tracks.isEmpty) return;

    final startLength = _baseQueue.length;
    _baseQueue = List<AudioTrack>.unmodifiable([..._baseQueue, ...tracks]);
    final newIndices = List<int>.generate(tracks.length, (i) => startLength + i);

    if (shuffleNotifier.value) {
      final updatedOrder = [..._playOrder, ...newIndices];
      updatedOrder.shuffle(_random);
      final keepBase = _clampBaseIndex(currentBaseIndex ?? 0);
      _ensureTrackIsFirst(updatedOrder, keepBase);
      _playOrder = List<int>.unmodifiable(updatedOrder);
      currentOrderIndexNotifier.value = orderIndexForBase(keepBase);
    } else {
      _playOrder = [..._playOrder, ...newIndices];
    }

    _notifyQueue();
    await _persistState();
  }

  Future<void> setCurrentOrderIndex(int orderIndex) async {
    if (_playOrder.isEmpty) return;
    final clamped = orderIndex.clamp(0, _playOrder.length - 1).toInt();
    currentOrderIndexNotifier.value = clamped;
    await _persistState();
  }

  Future<void> setCurrentBaseIndex(int baseIndex) async {
    final orderIndex = orderIndexForBase(baseIndex) ?? baseIndex;
    await setCurrentOrderIndex(orderIndex);
  }

  AudioTrack? trackForOrderIndex(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= _playOrder.length) return null;
    final baseIndex = _playOrder[orderIndex];
    if (baseIndex < 0 || baseIndex >= _baseQueue.length) return null;
    return _baseQueue[baseIndex];
  }

  int? nextOrderIndex() {
    final current = currentOrderIndexNotifier.value;
    if (current == null) return null;
    final next = current + 1;
    return next < _playOrder.length ? next : null;
  }

  int? previousOrderIndex() {
    final current = currentOrderIndexNotifier.value;
    if (current == null) return null;
    final prev = current - 1;
    return prev >= 0 ? prev : null;
  }

  int? orderIndexForBase(int baseIndex) {
    final idx = _playOrder.indexOf(baseIndex);
    return idx >= 0 ? idx : null;
  }

  Future<void> reshuffle({required int keepBaseIndex}) async {
    if (_baseQueue.isEmpty) return;
    shuffleNotifier.value = true;
    _playOrder = _buildShuffledOrder(startBaseIndex: keepBaseIndex);
    currentOrderIndexNotifier.value = 0;
    _notifyQueue();
    await _persistState();
  }

  Future<void> disableShuffle({required int keepBaseIndex}) async {
    if (_baseQueue.isEmpty) return;
    shuffleNotifier.value = false;
    _playOrder = List<int>.generate(_baseQueue.length, (i) => i);
    currentOrderIndexNotifier.value = orderIndexForBase(keepBaseIndex) ?? keepBaseIndex;
    _notifyQueue();
    await _persistState();
  }

  int? orderIndexOfCurrent() => currentOrderIndexNotifier.value;

  Future<int> persistentSizeBytes() async {
    final box = _box;
    if (box == null) return 0;
    final queue = box.get(_queueKey) as List? ?? const [];
    final order = box.get(_orderKey) as List? ?? const [];
    final serialized = jsonEncode({'q': queue, 'o': order});
    return utf8.encode(serialized).length;
  }

  List<int> _buildShuffledOrder({required int startBaseIndex}) {
    final order = List<int>.generate(_baseQueue.length, (i) => i);
    order.shuffle(_random);
    _ensureTrackIsFirst(order, _clampBaseIndex(startBaseIndex));
    return List<int>.unmodifiable(order);
  }

  void _ensureTrackIsFirst(List<int> order, int baseIndex) {
    final pos = order.indexOf(baseIndex);
    if (pos > 0) {
      order.removeAt(pos);
      order.insert(0, baseIndex);
    }
  }

  int _clampBaseIndex(int requested) {
    if (_baseQueue.isEmpty) return 0;
    return requested.clamp(0, _baseQueue.length - 1).toInt();
  }

  Future<void> _restoreState() async {
    if (_box == null) return;
    final storedQueue = _box!.get(_queueKey);
    final storedOrder = _box!.get(_orderKey);
    final storedIndex = _box!.get(_indexKey) as int?;
    final storedShuffle = _box!.get(_shuffleKey) as bool? ?? false;

    _baseQueue = _deserializeQueue(storedQueue);

    if (_baseQueue.isNotEmpty && storedOrder is List) {
      final normalized = storedOrder.whereType<int>().toList();
      final matchesLength = normalized.length == _baseQueue.length;
      final inRange = normalized.every((i) => i >= 0 && i < _baseQueue.length);
      _playOrder = matchesLength && inRange
          ? List<int>.unmodifiable(normalized)
          : List<int>.generate(_baseQueue.length, (i) => i);
    } else {
      _playOrder = _baseQueue.isEmpty
          ? const []
          : List<int>.generate(_baseQueue.length, (i) => i);
    }

    shuffleNotifier.value = storedShuffle && _baseQueue.isNotEmpty;

    if (_playOrder.isNotEmpty) {
      final idx = storedIndex ?? 0;
      currentOrderIndexNotifier.value =
          idx.clamp(0, _playOrder.length - 1).toInt();
    } else {
      currentOrderIndexNotifier.value = null;
    }

    _notifyQueue();
  }

  Future<void> _persistState() async {
    final box = _box;
    if (box == null) return;
    await box.put(
      _queueKey,
      _baseQueue.map(_serializeTrack).toList(growable: false),
    );
    await box.put(_orderKey, List<int>.from(_playOrder));
    await box.put(_indexKey, currentOrderIndexNotifier.value);
    await box.put(_shuffleKey, shuffleNotifier.value);
  }

  Map<String, dynamic> _serializeTrack(AudioTrack track) {
    return {
      'path': track.path,
      'title': track.title,
      'artist': track.artist,
      'durationMs': track.duration?.inMilliseconds,
    };
  }

  List<AudioTrack> _deserializeQueue(dynamic storedQueue) {
    if (storedQueue is List<AudioTrack>) {
      return List<AudioTrack>.unmodifiable(storedQueue);
    }
    if (storedQueue is List) {
      final tracks = storedQueue.whereType<Map>().map((entry) {
        final durationMs = entry['durationMs'] as int?;
        final path = entry['path'] as String? ?? '';
        if (path.isEmpty) return null;
        return AudioTrack(
          path: path,
          title: entry['title'] as String? ?? '',
          artist: entry['artist'] as String? ?? '',
          duration:
              durationMs != null ? Duration(milliseconds: durationMs) : null,
        );
      }).whereType<AudioTrack>().toList(growable: false);
      return List<AudioTrack>.unmodifiable(tracks);
    }
    return const [];
  }

  void _notifyQueue() {
    if (_playOrder.isEmpty || _baseQueue.isEmpty) {
      queueNotifier.value = const [];
      return;
    }
    final orderedTracks =
        _playOrder.map((i) => _baseQueue[i]).toList(growable: false);
    queueNotifier.value = List<AudioTrack>.unmodifiable(orderedTracks);
  }
}
