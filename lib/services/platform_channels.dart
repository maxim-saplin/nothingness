import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/song_info.dart';
import '../models/spectrum_settings.dart';

class PlatformChannels {
  static const _mediaChannel = MethodChannel('com.saplin.nothingness/media');
  static const _spectrumChannel = EventChannel('com.saplin.nothingness/spectrum');

  static final bool isAndroid = Platform.isAndroid;

  // Singleton
  static final PlatformChannels _instance = PlatformChannels._internal();
  factory PlatformChannels() => _instance;
  PlatformChannels._internal();

  // Check if notification access is granted
  Future<bool> isNotificationAccessGranted() async {
    if (!isAndroid) return false;
    try {
      return await _mediaChannel.invokeMethod<bool>('isNotificationAccessGranted') ?? false;
    } catch (e) {
      debugPrint('Error checking notification access: $e');
      return false;
    }
  }

  // Check if audio permission is granted
  Future<bool> hasAudioPermission() async {
    if (!isAndroid) return false;
    try {
      return await _mediaChannel.invokeMethod<bool>('hasAudioPermission') ?? false;
    } catch (e) {
      debugPrint('Error checking audio permission: $e');
      return false;
    }
  }

  // Request audio permission
  Future<void> requestAudioPermission() async {
    if (!isAndroid) return;
    try {
      await _mediaChannel.invokeMethod('requestAudioPermission');
    } catch (e) {
      debugPrint('Error requesting audio permission: $e');
    }
  }

  // Open notification settings
  Future<void> openNotificationSettings() async {
    if (!isAndroid) return;
    try {
      await _mediaChannel.invokeMethod('openNotificationSettings');
    } catch (e) {
      debugPrint('Error opening notification settings: $e');
    }
  }

  // Refresh media sessions
  Future<void> refreshSessions() async {
    if (!isAndroid) return;
    try {
      await _mediaChannel.invokeMethod('refreshSessions');
    } catch (e) {
      debugPrint('Error refreshing sessions: $e');
    }
  }

  // Get current song info
  Future<SongInfo?> getSongInfo() async {
    if (!isAndroid) return null;
    try {
      final result = await _mediaChannel.invokeMethod<Map<dynamic, dynamic>>('getSongInfo');
      if (result != null) {
        return SongInfo.fromMap(result);
      }
    } catch (e) {
      debugPrint('Error getting song info: $e');
    }
    return null;
  }

  // Media controls
  Future<void> playPause() async {
    if (!isAndroid) return;
    try {
      await _mediaChannel.invokeMethod('playPause');
    } catch (e) {
      debugPrint('Error play/pause: $e');
    }
  }

  Future<void> next() async {
    if (!isAndroid) return;
    try {
      await _mediaChannel.invokeMethod('next');
    } catch (e) {
      debugPrint('Error next: $e');
    }
  }

  Future<void> previous() async {
    if (!isAndroid) return;
    try {
      await _mediaChannel.invokeMethod('previous');
    } catch (e) {
      debugPrint('Error previous: $e');
    }
  }

  // Update spectrum settings on native side
  Future<void> updateSpectrumSettings(SpectrumSettings settings) async {
    if (!isAndroid) return;
    try {
      await _mediaChannel.invokeMethod('updateSpectrumSettings', settings.toJson());
    } catch (e) {
      debugPrint('Error updating spectrum settings: $e');
    }
  }

  // Stream for spectrum data
  Stream<List<double>> spectrumStream({int? sessionId}) {
    return _spectrumChannel.receiveBroadcastStream(sessionId).map((data) {
      if (data is List) {
        return data.map((e) => (e as num).toDouble()).toList();
      }
      return <double>[];
    }).handleError((error) {
      debugPrint('Spectrum stream error: $error');
    });
  }
}

