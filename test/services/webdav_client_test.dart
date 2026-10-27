import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nothingness/services/webdav_client.dart';

void main() {
  const accountRoot = 'https://cloud.example/remote.php/dav/files/alice';
  final requests = <http.Request>[];
  late WebDavClient client;

  setUp(() {
    requests.clear();
    client = WebDavClient(
      accountRoot: Uri.parse(accountRoot),
      username: 'alice',
      password: 'test-app-password',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          _directoryXml,
          207,
          headers: {'content-type': 'application/xml; charset=utf-8'},
        );
      }),
    );
  });

  test('PROPFIND parses a folder and URI-decoded child paths', () async {
    final listing = await client.listDirectory('Music');

    expect(requests, hasLength(1));
    expect(requests.single.method, 'PROPFIND');
    expect(requests.single.url.path, '/remote.php/dav/files/alice/Music');
    expect(requests.single.headers['Depth'], '1');
    expect(
      requests.single.headers['Authorization'],
      'Basic ${base64Encode(utf8.encode('alice:test-app-password'))}',
    );
    expect(requests.single.body, contains('<d:propfind'));
    expect(listing.isDirectory, isTrue);
    expect(listing.etag, '"music-v1"');
    expect(listing.entries, hasLength(2));

    final song = listing.entries.first;
    expect(song.name, 'Björk & Friends - Joga.opus');
    expect(song.relativePath, 'Music/Björk & Friends - Joga.opus');
    expect(song.isDirectory, isFalse);
    expect(song.size, 3);
    expect(song.etag, '"song-v1"');
    expect(song.contentType, 'audio/ogg');
    expect(listing.entries.last.isDirectory, isTrue);
  });

  test('GET carries If-Match and returns the response stream', () async {
    final getClient = WebDavClient(
      accountRoot: Uri.parse(accountRoot),
      username: 'alice',
      password: 'test-app-password',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'etag': '"song-v1"'},
        );
      }),
    );

    final response = await getClient.openFile(
      'Music/Björk & Friends - Joga.opus',
      etag: '"song-v1"',
    );
    expect(requests.single.method, 'GET');
    expect(
      requests.single.url.path,
      '/remote.php/dav/files/alice/Music/Bj%C3%B6rk%20&%20Friends%20-%20Joga.opus',
    );
    expect(requests.single.headers['If-Match'], '"song-v1"');
    expect(response.statusCode, 200);
    expect(await response.stream.toBytes(), [1, 2, 3]);
  });

  test('a non-folder PROPFIND response is rejected', () async {
    final fileClient = WebDavClient(
      accountRoot: Uri.parse(accountRoot),
      username: 'alice',
      password: 'test-app-password',
      client: MockClient((_) async => http.Response(_fileXml, 207)),
    );

    await expectLater(
      fileClient.listDirectory('Music/song.opus'),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.message,
          'message',
          contains('not a folder'),
        ),
      ),
    );
  });

  test('HTTP errors do not expose the app password', () async {
    final forbidden = WebDavClient(
      accountRoot: Uri.parse(accountRoot),
      username: 'alice',
      password: 'secret-do-not-print',
      client: MockClient((_) async => http.Response('Unauthorized', 401)),
    );

    await expectLater(
      forbidden.listDirectory('Music'),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.toString(),
          'description',
          allOf(contains('401'), isNot(contains('secret-do-not-print'))),
        ),
      ),
    );
  });
}

const _directoryXml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/alice/Music/</D:href>
    <D:propstat><D:prop>
      <D:displayname>Music</D:displayname><D:resourcetype><D:collection/></D:resourcetype>
      <D:getetag>"music-v1"</D:getetag>
    </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/alice/Music/Bj%C3%B6rk%20%26%20Friends%20-%20Joga.opus</D:href>
    <D:propstat><D:prop>
      <D:displayname>Björk &amp; Friends - Joga.opus</D:displayname>
      <D:resourcetype/><D:getcontentlength>3</D:getcontentlength>
      <D:getetag>"song-v1"</D:getetag><D:getcontenttype>audio/ogg</D:getcontenttype>
    </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/alice/Music/Live/</D:href>
    <D:propstat><D:prop>
      <D:displayname>Live</D:displayname><D:resourcetype><D:collection/></D:resourcetype>
      <D:getetag>"live-v1"</D:getetag>
    </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
</D:multistatus>''';

const _fileXml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/alice/Music/song.opus</D:href>
    <D:propstat><D:prop>
      <D:resourcetype/><D:getetag>"song-v1"</D:getetag>
    </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
</D:multistatus>''';
