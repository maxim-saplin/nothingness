import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/soloud_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scanFolder collects supported audio files recursively', () async {
    final tempDir = await Directory.systemTemp.createTemp('audio_scan');
    final subDir = Directory('${tempDir.path}/sub');
    await subDir.create(recursive: true);

    final files = [
      File('${tempDir.path}/a.mp3'),
      File('${tempDir.path}/b.txt'),
      File('${subDir.path}/c.flac'),
    ];
    for (final f in files) {
      await f.writeAsString('dummy');
    }

    final transport = SoLoudTransport();
    final controller = PlaybackController(transport: transport);
    final tracks = await controller.scanFolder(tempDir.path);

    expect(tracks.length, 2);
    expect(tracks.any((t) => t.path.endsWith('a.mp3')), isTrue);
    expect(tracks.any((t) => t.path.endsWith('c.flac')), isTrue);

    await controller.dispose();
  }, skip: Platform.isLinux);
}
