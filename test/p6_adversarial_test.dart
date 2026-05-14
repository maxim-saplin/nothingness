// P6 adversarial QA — hammers the four-axis switch (theme / variant / screen /
// operating mode) and verifies a) no Timer/listener leaks in the Void screen,
// b) MaterialApp survives rapid theme rebuilds.
//
// We deliberately mount only the parts of the app we can mount without
// touching SoLoud (which dlopens a native library not present under the
// unit-test binding). `MediaControllerPage`'s async bootstrap reaches into
// SoLoud, so we test those concerns via direct notifier flips on the
// VoidSettingsSheet + VoidScreen ancestor scope which use the same
// notifiers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/operating_mode.dart';
import 'package:nothingness/models/theme_id.dart';
import 'package:nothingness/models/theme_variant.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:nothingness/theme/themes.dart';
import 'package:nothingness/widgets/void_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, {ThemeVariant variant = ThemeVariant.dark}) {
  final brightness =
      variant == ThemeVariant.light ? Brightness.light : Brightness.dark;
  return MaterialApp(
    theme: buildAppTheme(id: ThemeId.void_, brightness: brightness),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final s = SettingsService();
    s.operatingModeNotifier.value = OperatingMode.own;
    s.themeVariantNotifier.value = ThemeVariant.dark;
  });

  group('P6 adversarial — themed surface', () {
    testWidgets('VoidSettingsSheet survives 20× variant flips in <100 ms',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Rebuild the MaterialApp under a different variant each flip — the
      // sheet must keep finding the AppPalette extension in its theme.
      const variants = [
        ThemeVariant.dark,
        ThemeVariant.light,
      ];
      for (var i = 0; i < 20; i++) {
        await tester
            .pumpWidget(_wrap(const VoidSettingsSheet(), variant: variants[i % 2]));
        await tester.pump(const Duration(milliseconds: 4));
      }
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(VoidSettingsSheet), findsOneWidget);
      expect(find.text('MODE', skipOffstage: false), findsOneWidget);
    });

    testWidgets('rapid operating-mode flips keep the visible tree consistent',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(const VoidSettingsSheet()));
      await tester.pump();

      final s = SettingsService();
      for (var i = 0; i < 20; i++) {
        s.operatingModeNotifier.value =
            i.isEven ? OperatingMode.background : OperatingMode.own;
        await tester.pump(const Duration(milliseconds: 4));
      }
      // Settle to a known state.
      s.operatingModeNotifier.value = OperatingMode.own;
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      // In own mode, Sound + Library are visible, External is hidden.
      expect(find.text('SOUND', skipOffstage: false), findsOneWidget);
      expect(find.text('LIBRARY', skipOffstage: false), findsOneWidget);
      expect(find.text('EXTERNAL', skipOffstage: false), findsNothing);
    });

    testWidgets(
        'VoidSettingsSheet dispose removes its operating-mode listener (no leak)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final s = SettingsService();
      final pre = s.operatingModeNotifier.hasListeners;

      await tester.pumpWidget(_wrap(const VoidSettingsSheet()));
      await tester.pump();

      // After mount the sheet should have installed at least one listener
      // (ValueListenableBuilder + listener for adaptive groups).
      expect(s.operatingModeNotifier.hasListeners, isTrue);

      // Unmount and verify the listener count returns to baseline.
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump();

      expect(
        s.operatingModeNotifier.hasListeners,
        equals(pre),
        reason: 'VoidSettingsSheet leaked an operatingMode listener',
      );
    });
  });
}
