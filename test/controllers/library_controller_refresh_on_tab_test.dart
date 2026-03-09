import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/controllers/library_controller.dart';
import 'package:nothingness/services/library_browser.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/services/media_store_freshness.dart';

class FakeMediaStoreFreshness implements MediaStoreFreshness {
  FakeMediaStoreFreshness({required bool dirty})
    : _dirty = ValueNotifier(dirty);

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
    required super.androidFolderRescan,
    super.waitForFolderRescan,
    super.folderRescanReloadDelays,
  });

  int refreshCalls = 0;

  @override
  Future<void> runRefreshLibraryFlow({
    bool manageScanningState = true,
    String? pathToReload,
  }) async {
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
        androidFolderRescan: (_) async => true,
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
        androidFolderRescan: (_) async => true,
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

  group('LibraryController.repairCurrentFolderListing', () {
    test('does nothing when not running on Android', () async {
      var rescanCalls = 0;
      final controller = TestLibraryController(
        libraryBrowser: FakeLibraryBrowser(),
        libraryService: _libraryServiceForTest(),
        mediaStoreFreshness: FakeMediaStoreFreshness(dirty: false),
        isAndroidOverride: false,
        androidFolderRescan: (_) async {
          rescanCalls += 1;
          return true;
        },
        folderRescanReloadDelays: const [Duration.zero],
        waitForFolderRescan: (_) async {},
      );
      controller.hasPermission = true;
      controller.currentPath = '/music';

      await controller.repairCurrentFolderListing();

      expect(rescanCalls, 0);
      expect(controller.refreshCalls, 0);
    });

    test('does nothing when no current folder is open', () async {
      var rescanCalls = 0;
      final controller = TestLibraryController(
        libraryBrowser: FakeLibraryBrowser(),
        libraryService: _libraryServiceForTest(),
        mediaStoreFreshness: FakeMediaStoreFreshness(dirty: false),
        isAndroidOverride: true,
        androidFolderRescan: (_) async {
          rescanCalls += 1;
          return true;
        },
        folderRescanReloadDelays: const [Duration.zero],
        waitForFolderRescan: (_) async {},
      );
      controller.hasPermission = true;

      await controller.repairCurrentFolderListing();

      expect(rescanCalls, 0);
      expect(controller.refreshCalls, 0);
    });

    test('does nothing while a scan is already in progress', () async {
      var rescanCalls = 0;
      final controller = TestLibraryController(
        libraryBrowser: FakeLibraryBrowser(),
        libraryService: _libraryServiceForTest(),
        mediaStoreFreshness: FakeMediaStoreFreshness(dirty: false),
        isAndroidOverride: true,
        androidFolderRescan: (_) async {
          rescanCalls += 1;
          return true;
        },
        folderRescanReloadDelays: const [Duration.zero],
        waitForFolderRescan: (_) async {},
      );
      controller.hasPermission = true;
      controller.currentPath = '/music';
      controller.isScanning = true;

      await controller.repairCurrentFolderListing();

      expect(rescanCalls, 0);
      expect(controller.refreshCalls, 0);
    });

    test(
      'rescans the current folder and then refreshes the library flow',
      () async {
        var rescanCalls = 0;
        String? rescannedPath;
        final controller = TestLibraryController(
          libraryBrowser: FakeLibraryBrowser(),
          libraryService: _libraryServiceForTest(),
          mediaStoreFreshness: FakeMediaStoreFreshness(dirty: false),
          isAndroidOverride: true,
          androidFolderRescan: (path) async {
            rescanCalls += 1;
            rescannedPath = path;
            return true;
          },
          folderRescanReloadDelays: const [Duration.zero],
          waitForFolderRescan: (_) async {},
        );
        controller.hasPermission = true;
        controller.currentPath = '/music';

        await controller.repairCurrentFolderListing();

        expect(rescanCalls, 1);
        expect(rescannedPath, '/music');
        expect(controller.refreshCalls, 1);
        expect(controller.error, isNull);
        expect(controller.isScanning, isFalse);
      },
    );
  });
}
