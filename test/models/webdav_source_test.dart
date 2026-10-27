import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/webdav_source.dart';

void main() {
  test(
    'WebDAV source round-trips snapshot configuration without a password',
    () {
      const source = WebDavSource(
        id: 'source-1',
        name: 'Music',
        serverUrl: 'https://cloud.example',
        username: 'alice',
        folderPath: 'Music',
        lastSyncedAtMs: 1234,
      );

      final json = source.toJson();
      expect(json, isNot(contains('password')));
      expect(WebDavSource.fromJson(json).toJson(), json);
    },
  );

  test('entry snapshot preserves WebDAV properties', () {
    final entry = WebDavEntry(
      name: 'Live.opus',
      relativePath: 'Music/Live.opus',
      isDirectory: false,
      size: 42,
      etag: '"etag"',
      lastModified: DateTime.utc(2025, 1, 2),
      contentType: 'audio/ogg',
    );

    expect(WebDavEntry.fromJson(entry.toJson()).toJson(), entry.toJson());
  });
}
