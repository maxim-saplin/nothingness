import 'dart:async';
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
    Random? random,
  })  : _hive = hive ?? Hive,
        _initHive = hiveInitializer ?? Hive.initFlutter,
        _openBox = boxOpener ?? ((hive) => hive.openBox<dynamic>(_boxName)),
        _random = random ?? Random();

  static const String _boxName = 'playlistBox';
  static const String _queueKey = 'queue';
  static const String _orderKey = 'order';
  static const String _indexKey = 'currentIndex';
  static const String _shuffleKey = 'shuffle';

  final HiveInterface _hive;
  final Future<void> Function() _initHive;
  final Future<Box<dynamic>> Function(HiveInterface) _openBox;
  final Random _random;

  // B-037: in-flight background persist so [dispose] awaits it before closing
  // the box (resume-index write is off the hot path but must survive shutdown).
  Future<void>? _pendingPersist;

  final ValueNotifier<List<AudioTrack>> queueNotifier = ValueNotifier(const []);
  final ValueNotifier<int?> currentOrderIndexNotifier = ValueNotifier(null);
  final ValueNotifier<bool> shuffleNotifier = ValueNotifier(false);

  Box<dynamic>? _box;
  List<AudioTrack> _baseQueue = const [];
  List<int> _playOrder = const [];

  int get length => _playOrder.length;
  int get baseLength => _baseQueue.length;

  int? get currentBaseIndex {
    final i = currentOrderIndexNotifier.value;
    return (i != null && i >= 0 && i < _playOrder.length) ? _playOrder[i] : null;
  }

  Future<void> init() async {
    await _initHive();
    _box ??= await _openBox(_hive);
    await _restoreState();
  }

  Future<void> dispose() async {
    // Let any background resume-index write land before closing the box.
    try {
      await _pendingPersist;
    } catch (_) {}
    await _box?.flush();
    await _box?.close();
  }

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startBaseIndex = 0,
    bool enableShuffle = false,
  }) async {
    if (tracks.isEmpty) {
      _baseQueue = const [];
      _playOrder = const [];
      currentOrderIndexNotifier.value = null;
      shuffleNotifier.value = false;
      queueNotifier.value = const [];
      return _persistState();
    }

    _baseQueue = List.unmodifiable(tracks);
    final baseIndex = _clampBaseIndex(startBaseIndex);
    shuffleNotifier.value = enableShuffle || shuffleNotifier.value;

    if (shuffleNotifier.value) {
      _playOrder = _shuffledOrderWithFirst(baseIndex);
      currentOrderIndexNotifier.value = 0;
    } else {
      _playOrder = _sequentialOrder();
      currentOrderIndexNotifier.value = baseIndex;
    }
    _notifyQueue();
    await _persistState();
  }

  Future<void> addTracks(List<AudioTrack> tracks) async {
    if (tracks.isEmpty) return;
    final start = _baseQueue.length;
    _baseQueue = List.unmodifiable([..._baseQueue, ...tracks]);
    final added = List<int>.generate(tracks.length, (i) => start + i);

    if (shuffleNotifier.value) {
      final order = [..._playOrder, ...added]..shuffle(_random);
      final keepBase = _clampBaseIndex(currentBaseIndex ?? 0);
      _ensureTrackIsFirst(order, keepBase);
      _playOrder = List.unmodifiable(order);
      currentOrderIndexNotifier.value = orderIndexForBase(keepBase);
    } else {
      _playOrder = [..._playOrder, ...added];
    }
    _notifyQueue();
    await _persistState();
  }

  Future<void> setCurrentOrderIndex(int orderIndex) async {
    if (_playOrder.isEmpty) return;
    currentOrderIndexNotifier.value =
        orderIndex.clamp(0, _playOrder.length - 1).toInt();
    // B-037: persist resume index off the hot path — notifier updates now, the
    // Hive write trails.
    _pendingPersist = _persistState();
    unawaited(_pendingPersist!.catchError((Object e) {
      debugPrint('[PlaylistStore] background persist failed: $e');
    }));
  }

  Future<void> setCurrentBaseIndex(int baseIndex) =>
      setCurrentOrderIndex(orderIndexForBase(baseIndex) ?? baseIndex);

  AudioTrack? trackForOrderIndex(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= _playOrder.length) return null;
    final base = _playOrder[orderIndex];
    return (base >= 0 && base < _baseQueue.length) ? _baseQueue[base] : null;
  }

  int? nextOrderIndex() {
    final cur = currentOrderIndexNotifier.value;
    if (cur == null) return null;
    return cur + 1 < _playOrder.length ? cur + 1 : null;
  }

  int? previousOrderIndex() {
    final cur = currentOrderIndexNotifier.value;
    if (cur == null) return null;
    return cur - 1 >= 0 ? cur - 1 : null;
  }

  int? orderIndexForBase(int baseIndex) {
    final i = _playOrder.indexOf(baseIndex);
    return i >= 0 ? i : null;
  }

  Future<void> reshuffle({required int keepBaseIndex}) async {
    if (_baseQueue.isEmpty) return;
    shuffleNotifier.value = true;
    _playOrder = List.unmodifiable(_shuffledIndices());
    currentOrderIndexNotifier.value = orderIndexForBase(keepBaseIndex) ?? 0;
    _notifyQueue();
    await _persistState();
  }

  Future<void> disableShuffle({required int keepBaseIndex}) async {
    if (_baseQueue.isEmpty) return;
    shuffleNotifier.value = false;
    _playOrder = _sequentialOrder();
    currentOrderIndexNotifier.value =
        orderIndexForBase(keepBaseIndex) ?? keepBaseIndex;
    _notifyQueue();
    await _persistState();
  }

  int? orderIndexOfCurrent() => currentOrderIndexNotifier.value;

  Future<int> persistentSizeBytes() async {
    final box = _box;
    if (box == null) return 0;
    final serialized = jsonEncode({
      'q': box.get(_queueKey) as List? ?? const [],
      'o': box.get(_orderKey) as List? ?? const [],
    });
    return utf8.encode(serialized).length;
  }

  List<int> _sequentialOrder() => List.generate(_baseQueue.length, (i) => i);

  List<int> _shuffledIndices() => _sequentialOrder()..shuffle(_random);

  List<int> _shuffledOrderWithFirst(int baseIndex) {
    final order = _shuffledIndices();
    _ensureTrackIsFirst(order, _clampBaseIndex(baseIndex));
    return List.unmodifiable(order);
  }

  void _ensureTrackIsFirst(List<int> order, int baseIndex) {
    final pos = order.indexOf(baseIndex);
    if (pos > 0) order.insert(0, order.removeAt(pos));
  }

  int _clampBaseIndex(int requested) =>
      _baseQueue.isEmpty ? 0 : requested.clamp(0, _baseQueue.length - 1).toInt();

  Future<void> _restoreState() async {
    final box = _box;
    if (box == null) return;
    _baseQueue = _deserializeQueue(box.get(_queueKey));
    final storedOrder = box.get(_orderKey);

    if (_baseQueue.isEmpty) {
      _playOrder = const [];
    } else if (storedOrder is List) {
      final normalized = storedOrder.whereType<int>().toList();
      final valid = normalized.length == _baseQueue.length &&
          normalized.every((i) => i >= 0 && i < _baseQueue.length);
      _playOrder = valid ? List.unmodifiable(normalized) : _sequentialOrder();
    } else {
      _playOrder = _sequentialOrder();
    }

    shuffleNotifier.value =
        (box.get(_shuffleKey) as bool? ?? false) && _baseQueue.isNotEmpty;

    if (_playOrder.isEmpty) {
      currentOrderIndexNotifier.value = null;
    } else {
      final idx = box.get(_indexKey) as int? ?? 0;
      currentOrderIndexNotifier.value =
          idx.clamp(0, _playOrder.length - 1).toInt();
    }
    _notifyQueue();
  }

  Future<void> _persistState() async {
    final box = _box;
    if (box == null) return;
    await box.put(_queueKey,
        _baseQueue.map(_serializeTrack).toList(growable: false));
    await box.put(_orderKey, List<int>.from(_playOrder));
    await box.put(_indexKey, currentOrderIndexNotifier.value);
    await box.put(_shuffleKey, shuffleNotifier.value);
  }

  Map<String, dynamic> _serializeTrack(AudioTrack track) => {
        'path': track.path,
        'title': track.title,
        'artist': track.artist,
        'durationMs': track.duration?.inMilliseconds,
      };

  List<AudioTrack> _deserializeQueue(dynamic stored) {
    if (stored is List<AudioTrack>) return List.unmodifiable(stored);
    if (stored is! List) return const [];
    final tracks = stored.whereType<Map>().map((entry) {
      final path = entry['path'] as String? ?? '';
      if (path.isEmpty) return null;
      final durationMs = entry['durationMs'] as int?;
      return AudioTrack(
        path: path,
        title: entry['title'] as String? ?? '',
        artist: entry['artist'] as String? ?? '',
        duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
      );
    }).whereType<AudioTrack>().toList(growable: false);
    return List.unmodifiable(tracks);
  }

  void _notifyQueue() {
    queueNotifier.value = _playOrder.isEmpty || _baseQueue.isEmpty
        ? const []
        : List.unmodifiable(_playOrder.map((i) => _baseQueue[i]));
  }
}
