import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/controllers/library_controller.dart';
import 'package:nothingness/providers/audio_player_provider.dart';
import 'package:nothingness/services/library_browser.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/services/media_store_freshness.dart';
import 'package:nothingness/widgets/library_panel.dart';
import 'package:provider/provider.dart';

class _FakeMediaStoreFreshness implements MediaStoreFreshness {
  _FakeMediaStoreFreshness() : _dirty = ValueNotifier<bool>(false);

  final ValueNotifier<bool> _dirty;

  @override
  ValueListenable<bool> get isDirty => _dirty;

  @override
  Future<bool> consumeIfChanged() async => false;
}

class _FakeLibraryBrowser extends LibraryBrowser {
  _FakeLibraryBrowser() : super(supportedExtensions: const {'mp3'});
}

class _PanelTestLibraryController extends LibraryController {
  _PanelTestLibraryController()
    : super(
        libraryBrowser: _FakeLibraryBrowser(),
        libraryService: LibraryService(),
        mediaStoreFreshness: _FakeMediaStoreFreshness(),
        isAndroidOverride: true,
        androidFolderRescan: (_) async => true,
        waitForFolderRescan: (_) async {},
        folderRescanReloadDelays: const [Duration.zero],
      );

  int repairCalls = 0;

  @override
  Future<void> repairCurrentFolderListing() async {
    repairCalls += 1;
  }
}

Widget _buildPanel(_PanelTestLibraryController controller) {
  final audioPlayerProvider = AudioPlayerProvider();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AudioPlayerProvider>.value(
        value: audioPlayerProvider,
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: LibraryPanel(
          isOpen: true,
          onClose: () {},
          controller: controller,
        ),
      ),
    ),
  );
}

Future<void> _openFoldersTab(WidgetTester tester) async {
  await tester.tap(find.text('Folders'));
  await tester.pumpAndSettle();
}

void main() {
  group('LibraryPanel repair button', () {
    testWidgets('is hidden in root view', (WidgetTester tester) async {
      final controller = _PanelTestLibraryController();
      controller.currentPath = null;

      await tester.pumpWidget(_buildPanel(controller));
      await _openFoldersTab(tester);

      expect(
        find.byKey(const Key('library-repair-folder-button')),
        findsNothing,
      );
    });

    testWidgets('is shown for an opened Android folder', (
      WidgetTester tester,
    ) async {
      final controller = _PanelTestLibraryController();
      controller.currentPath = '/storage/emulated/0/Music';

      await tester.pumpWidget(_buildPanel(controller));
      await _openFoldersTab(tester);

      expect(
        find.byKey(const Key('library-repair-folder-button')),
        findsOneWidget,
      );
      expect(find.text('Repair list'), findsOneWidget);
    });

    testWidgets('is disabled while scanning', (WidgetTester tester) async {
      final controller = _PanelTestLibraryController();
      controller.currentPath = '/storage/emulated/0/Music';
      controller.isScanning = true;

      await tester.pumpWidget(_buildPanel(controller));
      await _openFoldersTab(tester);

      final button = tester.widget<TextButton>(
        find.byKey(const Key('library-repair-folder-button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('triggers the controller repair action when tapped', (
      WidgetTester tester,
    ) async {
      final controller = _PanelTestLibraryController();
      controller.currentPath = '/storage/emulated/0/Music';

      await tester.pumpWidget(_buildPanel(controller));
      await _openFoldersTab(tester);

      await tester.tap(find.byKey(const Key('library-repair-folder-button')));
      await tester.pump();

      expect(controller.repairCalls, 1);
    });
  });
}
