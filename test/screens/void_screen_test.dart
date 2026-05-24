import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/screens/void_screen.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:nothingness/theme/app_typography.dart';
import 'package:nothingness/widgets/heroes/dot_hero.dart';
import 'package:nothingness/widgets/heroes/polo_hero.dart';
import 'package:nothingness/widgets/heroes/spectrum_hero.dart';
import 'package:nothingness/widgets/heroes/void_hero.dart';
import 'package:nothingness/widgets/transport_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/heroes/_test_helpers.dart';

Future<void> _pump(
  WidgetTester tester,
  ScreenConfig config,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final provider = FakeAudioPlayerProvider();
  await tester.pumpWidget(
    wrapWithProvider(
      provider,
      VoidScreen(config: config, settings: const SpectrumSettings()),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall methodCall) async => null,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SettingsService().immersiveNotifier.value = false;
  });

  group('VoidScreen hero dispatcher', () {
    testWidgets('void config → VoidHero', (tester) async {
      await _pump(tester, const VoidScreenConfig());
      expect(find.byType(VoidHero), findsOneWidget);
      expect(find.byType(SpectrumHero), findsNothing);
    });

    testWidgets('spectrum config → SpectrumHero', (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      expect(find.byType(SpectrumHero), findsOneWidget);
    });

    testWidgets('polo config → PoloHero', (tester) async {
      await _pump(tester, const PoloScreenConfig());
      expect(find.byType(PoloHero), findsOneWidget);
    });

    testWidgets('dot config → DotHero', (tester) async {
      await _pump(tester, const DotScreenConfig());
      expect(find.byType(DotHero), findsOneWidget);
    });
  });

  group('VoidScreen transport row visibility', () {
    testWidgets('non-immersive shows transport row', (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      expect(find.byType(TransportRow), findsOneWidget);
    });

    testWidgets('immersive hides transport row', (tester) async {
      SettingsService().immersiveNotifier.value = true;
      await _pump(tester, const SpectrumScreenConfig());
      // Pump the immersive animation through.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TransportRow), findsNothing);
    });
  });

  group('VoidScreen search crumb (B-013)', () {
    // Helper: enter search mode by long-pressing the crumb.
    Future<void> openSearch(WidgetTester tester) async {
      // Long-press by tap-down + hold + release. We target the path readout
      // (the "~" text rendered by MidEllipsis at the bottom crumb slot).
      // Use the bottom crumb position via TestGesture.
      final crumb = find.text('~');
      expect(crumb, findsOneWidget);
      await tester.longPress(crumb);
      await tester.pumpAndSettle();
    }

    testWidgets('search input renders at row-size (typography.rowSize)',
        (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      await openSearch(tester);

      // The TextField is the input. Find it inside the search crumb.
      final tfFinder = find.byType(TextField);
      expect(tfFinder, findsOneWidget);
      final tf = tester.widget<TextField>(tfFinder);
      final fontSize = tf.style?.fontSize;
      expect(fontSize, isNotNull);

      // Read the typography from the same theme our build used.
      final context = tester.element(tfFinder);
      final typography = Theme.of(context).extension<AppTypography>()!;
      expect(fontSize, equals(typography.rowSize),
          reason: 'B-013: search input must match row-size, not crumbSize.');
    });

    testWidgets('tap on void-search-close ValueKey closes search',
        (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      await openSearch(tester);
      expect(find.byType(TextField), findsOneWidget);

      final closeFinder = find.byKey(const ValueKey('void-search-close'));
      expect(closeFinder, findsOneWidget,
          reason: 'B-013: × must be reachable by ValueKey for QA tap.');
      await tester.tap(closeFinder);
      await tester.pumpAndSettle();

      // Search mode collapsed: no TextField, crumb shows "~" again.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('~'), findsOneWidget);
    });

    testWidgets('vertical swipe-down on crumb closes search', (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      await openSearch(tester);
      expect(find.byType(TextField), findsOneWidget);

      // Target the search-crumb gesture region by ValueKey.
      final crumbRegion =
          find.byKey(const ValueKey('void-search-crumb-region'));
      expect(crumbRegion, findsOneWidget,
          reason: 'B-013: search crumb must expose a drag-down dismissal '
              'gesture region.');
      await tester.fling(crumbRegion, const Offset(0, 200), 1000);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('~'), findsOneWidget);
    });

    testWidgets(
        'focus-out collapses search even with a non-empty query (B-013)',
        (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      await openSearch(tester);

      final tfFinder = find.byType(TextField);
      expect(tfFinder, findsOneWidget);
      await tester.enterText(tfFinder, 'the');
      await tester.pump();

      // Drop focus by unfocusing the primary focus owner directly. This
      // mimics tapping elsewhere on the screen (defocusing the field).
      final tfContext = tester.element(tfFinder);
      FocusScope.of(tfContext).unfocus();
      await tester.pumpAndSettle();

      // Per B-013 policy: focus-out collapses regardless of query.
      expect(find.byType(TextField), findsNothing,
          reason: 'B-013: focus-out must collapse search even with a '
              'non-empty query.');
      expect(find.text('~'), findsOneWidget);
    });
  });
}
