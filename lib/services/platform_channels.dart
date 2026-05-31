import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/song_info.dart';
import '../models/spectrum_settings.dart';

class PlatformChannels {
  static const _mediaChannel = MethodChannel('com.saplin.nothingness/media');
  static const _spectrumChannel = EventChannel(
    'com.saplin.nothingness/spectrum',
  );
  static const _mediaStoreChannel = MethodChannel(
    'com.saplin.nothingness/mediastore',
  );
  static const _mediaStoreEvents = EventChannel(
    'com.saplin.nothingness/mediastore/events',
  );

  static final bool isAndroid = Platform.isAndroid;

  static final PlatformChannels _instance = PlatformChannels._internal();
  factory PlatformChannels() => _instance;
  PlatformChannels._internal();

  /// Android-only `invokeMethod` wrapper: no-ops off Android and swallows
  /// errors after logging [errorLabel], returning [fallback].
  Future<T> _invoke<T>(
    MethodChannel channel,
    String method,
    String errorLabel,
    T fallback, {
    Object? arguments,
  }) async {
    if (!isAndroid) return fallback;
    try {
      final result = await channel.invokeMethod<T>(method, arguments);
      return result ?? fallback;
    } catch (e) {
      debugPrint('$errorLabel: $e');
      return fallback;
    }
  }

  Future<bool> isNotificationAccessGranted() => _invoke(
    _mediaChannel,
    'isNotificationAccessGranted',
    'Error checking notification access',
    false,
  );

  Future<bool> hasAudioPermission() => _invoke(
    _mediaChannel,
    'hasAudioPermission',
    'Error checking audio permission',
    false,
  );

  Future<void> requestAudioPermission() => _invoke<void>(
    _mediaChannel,
    'requestAudioPermission',
    'Error requesting audio permission',
    null,
  );

  Future<void> openNotificationSettings() => _invoke<void>(
    _mediaChannel,
    'openNotificationSettings',
    'Error opening notification settings',
    null,
  );

  Future<void> refreshSessions() => _invoke<void>(
    _mediaChannel,
    'refreshSessions',
    'Error refreshing sessions',
    null,
  );

  Future<SongInfo?> getSongInfo() async {
    if (!isAndroid) return null;
    try {
      final result = await _mediaChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getSongInfo',
      );
      if (result != null) {
        return SongInfo.fromMap(result);
      }
    } catch (e) {
      debugPrint('Error getting song info: $e');
    }
    return null;
  }

  Future<void> playPause() =>
      _invoke<void>(_mediaChannel, 'playPause', 'Error play/pause', null);

  Future<void> next() =>
      _invoke<void>(_mediaChannel, 'next', 'Error next', null);

  Future<void> previous() =>
      _invoke<void>(_mediaChannel, 'previous', 'Error previous', null);

  /// Dispatches a media-key event to the active external `MediaSession` (used
  /// in background mode). [keyCode] mirrors `android.view.KeyEvent`. Native
  /// tries the listener active-controller path, then `AudioManager`; no-op off
  /// Android.
  Future<void> dispatchExternalMediaKey(int keyCode) => _invoke<void>(
    _mediaChannel,
    'dispatchExternalMediaKey',
    'Error dispatchExternalMediaKey',
    null,
    arguments: <String, Object?>{'keyCode': keyCode},
  );

  // Android KeyEvent codes used in background mode.
  static const int keyCodeMediaPlayPause = 85;
  static const int keyCodeMediaNext = 87;
  static const int keyCodeMediaPrevious = 88;

  Future<void> updateSpectrumSettings(SpectrumSettings settings) =>
      _invoke<void>(
        _mediaChannel,
        'updateSpectrumSettings',
        'Error updating spectrum settings',
        null,
        arguments: settings.toJson(),
      );

  Stream<List<double>> spectrumStream({int? sessionId}) {
    return _spectrumChannel
        .receiveBroadcastStream(sessionId)
        .map((data) {
          if (data is List) {
            return data.map((e) => (e as num).toDouble()).toList();
          }
          return <double>[];
        })
        .handleError((error) {
          debugPrint('Spectrum stream error: $error');
        });
  }

  /// Android 11+ MediaStore version string. Returns null if unavailable.
  Future<String?> getMediaStoreVersion() async {
    if (!isAndroid) return null;
    try {
      return await _mediaStoreChannel.invokeMethod<String>(
        'getMediaStoreVersion',
      );
    } catch (e) {
      debugPrint('Error getting MediaStore version: $e');
      return null;
    }
  }

  /// Requests a direct-file MediaStore rescan for the given Android folder.
  /// Returns true once scan requests are issued (not propagation completion).
  Future<bool> rescanFolder(String path) async {
    if (path.isEmpty) return false;
    return _invoke(
      _mediaStoreChannel,
      'rescanFolder',
      'Error rescanning MediaStore folder $path',
      false,
      arguments: <String, Object?>{'path': path},
    );
  }

  /// Stream that emits when MediaStore reports changes (ContentObserver).
  Stream<void> mediaStoreChanges() {
    if (!isAndroid) return const Stream<void>.empty();
    return _mediaStoreEvents
        .receiveBroadcastStream()
        .map((_) => null)
        .handleError((error) {
          debugPrint('MediaStore stream error: $error');
        });
  }
}
