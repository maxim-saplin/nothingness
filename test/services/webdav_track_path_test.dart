import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/webdav_track_path.dart';

void main() {
  test('remote track IDs encode each account-relative path segment', () {
    final path = WebDavTrackPath.encode(
      'source-1',
      'Music/Live/Björk & Sigur Rós - #1.opus',
    );

    expect(path, startsWith('webdav://source-1/'));
    expect(
      WebDavTrackPath.relativePath(path),
      'Music/Live/Björk & Sigur Rós - #1.opus',
    );
    expect(WebDavTrackPath.sourceId(path), 'source-1');
    expect(WebDavTrackPath.basename(path), 'Björk & Sigur Rós - #1.opus');
    expect(
      WebDavTrackPath.parent(path),
      WebDavTrackPath.encode('source-1', 'Music/Live'),
    );
    expect(WebDavTrackPath.isRemote(path), isTrue);
  });

  test('source root parent is the account root', () {
    expect(
      WebDavTrackPath.parent('webdav://source-1/Music'),
      WebDavTrackPath.root('source-1'),
    );
    expect(WebDavTrackPath.relativePath(WebDavTrackPath.root('source-1')), '');
  });
}
