import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/screens/void_screen.dart';
import 'package:nothingness/services/settings_service.dart';
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
}
