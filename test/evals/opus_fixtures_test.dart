import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const fixtureDirectory = 'evals/assets/opus';

void main() {
  final manifest = (jsonDecode(
    File('$fixtureDirectory/manifest.json').readAsStringSync(),
  ) as List<dynamic>).cast<Map<String, dynamic>>();

  test('Opus fixture manifest covers exactly ten committed files', () {
    final files = Directory(fixtureDirectory)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.opus'))
        .map((file) => file.path)
        .toList()
      ..sort();
    final paths = manifest.map((entry) => entry['path'] as String).toList()
      ..sort();

    expect(manifest, hasLength(10));
    expect(files, paths);
    expect(paths.toSet(), hasLength(10));
  });

  test('Opus fixtures match their hashes and media metadata', () {
    for (final entry in manifest) {
      final path = entry['path'] as String;
      final hash = Process.runSync('shasum', ['-a', '256', path]);
      expect(hash.exitCode, 0, reason: hash.stderr as String?);
      expect(
        (hash.stdout as String).split(' ').first,
        entry['sha256'],
        reason: path,
      );

      final probe = Process.runSync('ffprobe', [
        '-v',
        'error',
        '-show_entries',
        'stream=codec_name,sample_rate,channels:stream_tags=title,artist,album:format=duration',
        '-of',
        'json',
        path,
      ]);
      expect(probe.exitCode, 0, reason: probe.stderr as String?);

      final media = jsonDecode(probe.stdout as String) as Map<String, dynamic>;
      final stream = (media['streams'] as List<dynamic>).single
          as Map<String, dynamic>;
      final format = media['format'] as Map<String, dynamic>;
        final tags = stream['tags'] as Map<String, dynamic>;

      expect(stream['codec_name'], 'opus', reason: path);
      expect(int.parse(stream['sample_rate'] as String), entry['sample_rate']);
      expect(stream['channels'], entry['channels']);
      expect(
        double.parse(format['duration'] as String),
        closeTo(entry['duration_seconds'] as double, 0.01),
      );
      expect(tags['title'], entry['title']);
      expect(tags['artist'], entry['artist']);
      expect(tags['album'], entry['album']);
    }
  });
}