import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/operating_mode.dart';
import 'package:nothingness/models/theme_id.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:nothingness/theme/themes.dart';
import 'package:nothingness/widgets/void_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(id: ThemeId.void_, brightness: Brightness.dark),
    home: child,
  );
}

/// Pump the sheet in a tall viewport so every list row is realised. The
/// default Flutter test surface (800x600) clips the bottom rows of the
/// Void settings list because `ListView` lazily builds off-screen items.
Future<void> _pumpInTallViewport(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  await tester.pumpWidget(app);
  await tester.pump();
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub SystemChrome so SettingsService.setFullScreen (called as a side effect
  // of cycling rows) does not blow up under the test binding.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall methodCall) async => null,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Reset notifiers on the singleton between tests so visibility predicates
    // don't leak across cases.
    final s = SettingsService();
    s.operatingModeNotifier.value = OperatingMode.own;
  });

  group('VoidSettingsSheet — group visibility predicates', () {
    testWidgets('own mode: Sound + Library visible, External hidden',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.own;

      await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

      // Mode + Look always present.
      expect(find.text('MODE', skipOffstage: false), findsOneWidget);
      expect(find.text('LOOK', skipOffstage: false), findsOneWidget);

      // Own mode reveals Sound + Library.
      expect(find.text('SOUND', skipOffstage: false), findsOneWidget);
      expect(find.text('LIBRARY', skipOffstage: false), findsOneWidget);

      // External must be hidden in own mode.
      expect(find.text('EXTERNAL', skipOffstage: false), findsNothing);

      // Display + About always present.
      expect(find.text('DISPLAY', skipOffstage: false), findsOneWidget);
      expect(find.text('ABOUT', skipOffstage: false), findsOneWidget);
    });

    testWidgets('background mode: External visible, Sound + Library hidden',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.background;

      await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

      expect(find.text('MODE', skipOffstage: false), findsOneWidget);
      expect(find.text('LOOK', skipOffstage: false), findsOneWidget);
      expect(find.text('SOUND', skipOffstage: false), findsNothing);
      expect(find.text('LIBRARY', skipOffstage: false), findsNothing);
      expect(find.text('EXTERNAL', skipOffstage: false), findsOneWidget);
      expect(find.text('DISPLAY', skipOffstage: false), findsOneWidget);
      expect(find.text('ABOUT', skipOffstage: false), findsOneWidget);
    });

    testWidgets('mode flip updates visibility within a frame',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.own;

      await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

      expect(find.text('SOUND', skipOffstage: false), findsOneWidget);
      expect(find.text('EXTERNAL', skipOffstage: false), findsNothing);

      // Flip mode directly on the notifier — the sheet must rebuild from the
      // ValueListenableBuilder, no rebuild trigger from outside.
      SettingsService().operatingModeNotifier.value = OperatingMode.background;
      await tester.pump();

      expect(find.text('SOUND', skipOffstage: false), findsNothing);
      expect(find.text('EXTERNAL', skipOffstage: false), findsOneWidget);
    });
  });

  group('VoidSettingsSheet — reachable rows', () {
    testWidgets('own mode exposes the mode + look + sound + library + display + about rows',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.own;

      await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

      // Spot-check each group has at least its key row. Many rows sit below
      // the viewport in a ListView; pass skipOffstage:false so the finder
      // searches the full widget tree, not just the rendered viewport.
      Finder byK(String k) =>
          find.byKey(ValueKey(k), skipOffstage: false);

      expect(byK('void-settings-mode'), findsOneWidget);
      expect(byK('void-settings-theme'), findsOneWidget);
      expect(byK('void-settings-variant'), findsOneWidget);
      expect(byK('void-settings-screen'), findsOneWidget);
      expect(byK('void-settings-ui-scale'), findsOneWidget);
      expect(byK('void-settings-full-screen'), findsOneWidget);
      expect(byK('void-settings-eq'), findsOneWidget);
      expect(byK('void-settings-smart-folders'), findsOneWidget);
      expect(byK('void-settings-logs'), findsOneWidget);
      expect(byK('void-settings-audio-diagnostics'), findsOneWidget);
      expect(byK('void-settings-version'), findsOneWidget);

      // Background-only rows must NOT be reachable in own mode.
      expect(byK('void-settings-noise-gate'), findsNothing);
      expect(byK('void-settings-mic-permission'), findsNothing);
    });

    testWidgets('background mode hides library + sound rows',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.background;

      await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

      Finder byK(String k) =>
          find.byKey(ValueKey(k), skipOffstage: false);

      // Own-only rows must NOT be reachable in background mode.
      expect(byK('void-settings-smart-folders'), findsNothing);
      expect(byK('void-settings-scan-on-startup'), findsNothing);
      expect(byK('void-settings-eq'), findsNothing);

      // Background rows are reachable.
      expect(byK('void-settings-noise-gate'), findsOneWidget);
    });
  });

  group('VoidSettingsSheet — row interactions persist', () {
    testWidgets('smart folders toggle writes to settings service',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.own;
      // Force a known starting value.
      await SettingsService().setSmartFoldersPresentation(true);

      await tester.pumpWidget(_wrap(const VoidSettingsSheet()));
      await tester.pump();

      // Smart folders sits below the viewport in tall sheets — scroll until
      // visible so the tap dispatches to the rendered widget.
      final rowFinder =
          find.byKey(const ValueKey('void-settings-smart-folders'));
      await tester.scrollUntilVisible(
        rowFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(rowFinder);
      await tester.pump();

      expect(
        SettingsService().smartFoldersPresentationNotifier.value,
        isFalse,
      );
    });

    testWidgets('mode row cycles operating mode',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.own;

      await tester.pumpWidget(_wrap(const VoidSettingsSheet()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('void-settings-mode')));
      await tester.pump();

      expect(
        SettingsService().operatingModeNotifier.value,
        OperatingMode.background,
      );
    });
  });
}
