import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/soloud_transport.dart';

/// Guards the opus fix: the buffer-stream feed is CHUNKED (fed in pieces with
/// yields between), not one synchronous whole-file call that froze the UI.
void main() {
  test('splits a multi-MB buffer into 128KB chunks (not one)', () {
    final bytes = Uint8List(6 * 1024 * 1024 + 7); // ~6MB opus, not chunk-aligned
    final chunks = audioStreamChunks(bytes).toList();

    expect(chunks.length, 49, reason: 'ceil(6MB+7 / 128KB) = 49 chunks');
    expect(chunks.first.length, 128 * 1024);
    expect(chunks.last.length, 7, reason: 'remainder chunk');
    // Re-joining the views must reproduce the original length exactly.
    expect(chunks.fold<int>(0, (s, c) => s + c.length), bytes.length);
  });

  test('small buffer is a single chunk', () {
    final chunks = audioStreamChunks(Uint8List(1000)).toList();
    expect(chunks.length, 1);
    expect(chunks.single.length, 1000);
  });

  test('empty buffer yields nothing', () {
    expect(audioStreamChunks(Uint8List(0)).toList(), isEmpty);
  });

  test('respects a custom chunk size', () {
    final chunks = audioStreamChunks(Uint8List(250), chunkSize: 100).toList();
    expect(chunks.map((c) => c.length), [100, 100, 50]);
  });
}
