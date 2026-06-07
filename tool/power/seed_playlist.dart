import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/power/seed_playlist.dart <out-dir> <track-path>',
    );
    exitCode = 64;
    return;
  }

  final outDir = Directory(args[0]);
  final trackPath = args[1];
  await outDir.create(recursive: true);

  Hive.init(outDir.path);
  final box = await Hive.openBox<dynamic>('playlistBox');
  await box.put('queue', <Map<String, dynamic>>[
    <String, dynamic>{
      'path': trackPath,
      'title': p.basename(trackPath),
      'artist': 'diagnostic',
      'durationMs': null,
    },
  ]);
  await box.put('order', <int>[0]);
  await box.put('currentIndex', 0);
  await box.put('shuffle', false);
  await box.flush();
  await box.close();
}