import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/android_audio_source.dart';

/// Covers the Dart side of CHANGE B (content-URI playback): the platform-channel
/// contract that turns a `_data` path into playable bytes. The Kotlin
/// resolution + ContentResolver read is validated live on Android.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.saplin.nothingness/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('returns the bytes the platform yields and passes the path', () async {
    String? seenMethod;
    String? seenPath;
    final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
    messenger.setMockMethodCallHandler(channel, (call) async {
      seenMethod = call.method;
      seenPath = (call.arguments as Map)['path'] as String?;
      return bytes;
    });

    final result = await readAudioBytesViaChannel('/storage/emulated/0/Music/x.wav');

    expect(seenMethod, 'readAudioBytes');
    expect(seenPath, '/storage/emulated/0/Music/x.wav');
    expect(result, bytes);
  });

  test('returns null (→ caller falls back to file load) when the platform '
      'reports an error', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'IO', message: 'unreadable');
    });

    expect(await readAudioBytesViaChannel('/storage/emulated/0/Music/x.wav'), isNull);
  });

  test('returns null when the platform yields null (path not in MediaStore)',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await readAudioBytesViaChannel('/storage/emulated/0/Music/x.wav'), isNull);
  });

  test('empty path short-circuits without hitting the channel', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return null;
    });
    expect(await readAudioBytesViaChannel(''), isNull);
    expect(called, isFalse);
  });
}
