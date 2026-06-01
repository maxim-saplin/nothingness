import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _mediaChannel = MethodChannel('com.saplin.nothingness/media');

/// Reads audio bytes for [path] via a MediaStore `content://` URI on Android.
///
/// Android 11+ scoped storage blocks raw-path `File`/native access to shared
/// storage (`/storage/emulated/0/...`); `READ_MEDIA_AUDIO` only grants access
/// through MediaStore. The Kotlin side resolves the `_data` path to a content
/// URI and streams its bytes. Returns null when not on Android, the path can't
/// be resolved in MediaStore, or the read fails — the caller then falls back to
/// a direct file load (correct for desktop and app-private paths).
Future<Uint8List?> readAndroidAudioBytes(String path) async {
  if (!Platform.isAndroid) return null;
  return readAudioBytesViaChannel(path);
}

/// B-049 spike: open [path] as a content-URI file descriptor and return a
/// `/proc/self/fd/N` path. SoLoud's `loadFile` reads+decodes it in the compute
/// isolate, so no whole-file bytes cross onto the UI isolate. Caller MUST
/// [closeAndroidAudioFd] after the load to release the descriptor.
Future<String?> openAndroidAudioFd(String path) async {
  if (!Platform.isAndroid || path.isEmpty) return null;
  try {
    return await _mediaChannel
        .invokeMethod<String>('openAudioFd', <String, dynamic>{'path': path});
  } catch (e) {
    debugPrint('[android_audio_source] openAudioFd failed for $path: $e');
    return null;
  }
}

/// Releases a descriptor opened by [openAndroidAudioFd] ([fdPath] = /proc/self/fd/N).
Future<void> closeAndroidAudioFd(String fdPath) async {
  final n = int.tryParse(fdPath.split('/').last);
  if (n == null) return;
  try {
    await _mediaChannel.invokeMethod<void>('closeAudioFd', <String, dynamic>{'fd': n});
  } catch (_) {}
}

/// The channel call without the platform guard, so it's exercisable in tests
/// (the host platform isn't Android).
@visibleForTesting
Future<Uint8List?> readAudioBytesViaChannel(String path) async {
  if (path.isEmpty) return null;
  try {
    return await _mediaChannel
        .invokeMethod<Uint8List>('readAudioBytes', <String, dynamic>{'path': path});
  } catch (e) {
    debugPrint('[android_audio_source] readAudioBytes failed for $path: $e');
    return null;
  }
}
