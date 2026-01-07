import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/controllers/library_controller.dart';
import 'package:nothingness/services/library_browser.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/services/media_store_freshness.dart';

class FakeMediaStoreFreshness implements MediaStoreFreshness {
  FakeMediaStoreFreshness({required bool dirty}) : _dirty = ValueNotifier(dirty);

  final ValueNotifier<bool> _dirty;

  @override
  ValueListenable<bool> get isDirty => _dirty;

  int consumeCalls = 0;

  @override
  Future<bool> consumeIfChanged() async {
    consumeCalls += 1;
    if (_dirty.value) {
      _dirty.value = false;
      return true;
    }
    return false;
  }
}

// Note: LibraryService is a singleton with internal Hive usage; tests in this
// file avoid exercising those methods. We still need an instance to satisfy the
// controller constructor.
LibraryService _libraryServiceForTest() => LibraryService();

class FakeLibraryBrowser extends LibraryBrowser {
  FakeLibraryBrowser() : super(supportedExtensions: const {'mp3'});
}

class TestLibraryController extends LibraryController {
  TestLibraryController({
    required super.libraryBrowser,
    required super.libraryService,
    required super.mediaStoreFreshness,
    required super.isAndroidOverride,
  });

  int refreshCalls = 0;

  @override
  Future<void> refreshLibrary() async {
    refreshCalls += 1;
  }
}

void main() {
  group('LibraryController.onFoldersTabVisible', () {
    test('does nothing when MediaStore is not dirty', () async {
      final freshness = FakeMediaStoreFreshness(dirty: false);
      final controller = TestLibraryController(
        libraryBrowser: FakeLibraryBrowser(),
        libraryService: _libraryServiceForTest(),
        mediaStoreFreshness: freshness,
        isAndroidOverride: true,
      );
      controller.hasPermission = true;

      await controller.onFoldersTabVisible();

      expect(freshness.consumeCalls, 1);
      expect(controller.refreshCalls, 0);
    });

    test('refreshes when MediaStore is dirty', () async {
      final freshness = FakeMediaStoreFreshness(dirty: true);
      final controller = TestLibraryController(
        libraryBrowser: FakeLibraryBrowser(),
        libraryService: _libraryServiceForTest(),
        mediaStoreFreshness: freshness,
        isAndroidOverride: true,
      );
      controller.hasPermission = true;

      await controller.onFoldersTabVisible();

      expect(freshness.consumeCalls, 1);
      expect(controller.refreshCalls, 1);

      // Subsequent call should no-op (dirty consumed).
      await controller.onFoldersTabVisible();
      expect(freshness.consumeCalls, 2);
      expect(controller.refreshCalls, 1);
    });
  });
}


