import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nothingness/services/library_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryService', () {
    late Directory tempDir;

    setUp(() async {
      // Create a temporary directory in the system temp folder
      // We don't use path_provider here to avoid channel mocking issues if possible,
      // but LibraryService might use it internally?
      // Checking LibraryService code:
      // It uses Hive.openBox. Hive.init needs a path.
      // In the test, we call Hive.init(tempDir.path).
      // But wait, the previous error was "MissingPluginException ... getTemporaryDirectory".
      // This call was in my setUp() in the previous version of the test!
      // "tempDir = await getTemporaryDirectory();"
      
      // So I just need to use Directory.systemTemp instead of path_provider in the test setup.
      tempDir = await Directory.systemTemp.createTemp('library_service_test');
      Hive.init(tempDir.path);
      
      // Also, LibraryService uses path_provider?
      // Reading LibraryService code again:
      // It does NOT import path_provider. It uses Hive.
      // So the MissingPluginException came purely from my test setup using getTemporaryDirectory().
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tempDir.delete(recursive: true);
    });

    test('singleton returns same instance', () {
      final s1 = LibraryService();
      final s2 = LibraryService();
      expect(s1, same(s2));
    });

    test('timestamp persistence works on Android', () async {
      final service = LibraryService();
      await service.init();
      
      await service.setLastScanTimestamp(123456789);
      final ts = service.getLastScanTimestamp();
      
      if (Platform.isAndroid) {
        expect(ts, 123456789);
      } else {
        expect(ts, null);
      }
    });
  });
}
