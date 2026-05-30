import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/operating_mode.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/theme_id.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:nothingness/theme/themes.dart';
import 'package:nothingness/widgets/void_settings_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mock_audio_transport.dart';

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

      await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

      // In the tall viewport every row is realised; tap by key directly.
      final rowFinder =
          find.byKey(const ValueKey('void-settings-smart-folders'));
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

  group('VoidSettingsSheet — status strip (B-016)', () {
    testWidgets(
      'status strip is visible above the MODE group when queue is non-empty',
      (tester) async {
        SettingsService().operatingModeNotifier.value = OperatingMode.own;
        final provider = _StubAudioProvider(
          queue: const [
            AudioTrack(path: '/a.mp3', title: 'a', artist: 'A'),
            AudioTrack(path: '/b.mp3', title: 'b', artist: 'B'),
          ],
          shuffle: false,
        );

        await _pumpInTallViewport(
          tester,
          _wrap(
            ChangeNotifierProvider<PlaybackController>.value(
              value: provider,
              child: const VoidSettingsSheet(),
            ),
          ),
        );

        final queueRow = find.byKey(
          const ValueKey('void-settings-status-queue'),
          skipOffstage: false,
        );
        final shuffleRow = find.byKey(
          const ValueKey('void-settings-status-shuffle'),
          skipOffstage: false,
        );
        final modeHeader = find.text('MODE', skipOffstage: false);

        expect(queueRow, findsOneWidget);
        expect(shuffleRow, findsOneWidget);
        expect(modeHeader, findsOneWidget);

        // The status rows must sit above the MODE group header visually.
        final queueY =
            tester.getTopLeft(queueRow).dy;
        final shuffleY =
            tester.getTopLeft(shuffleRow).dy;
        final modeY = tester.getTopLeft(modeHeader).dy;

        expect(queueY < modeY, isTrue,
            reason: 'queue row should be above MODE header');
        expect(shuffleY < modeY, isTrue,
            reason: 'shuffle row should be above MODE header');
      },
    );

    testWidgets('queue count text matches provider queue length',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.own;
      final provider = _StubAudioProvider(
        queue: const [
          AudioTrack(path: '/a.mp3', title: 'a'),
          AudioTrack(path: '/b.mp3', title: 'b'),
          AudioTrack(path: '/c.mp3', title: 'c'),
        ],
        shuffle: false,
      );

      await _pumpInTallViewport(
        tester,
        _wrap(
          ChangeNotifierProvider<PlaybackController>.value(
            value: provider,
            child: const VoidSettingsSheet(),
          ),
        ),
      );

      // Locate the queue row by stable key, then confirm the value text shows
      // the queue length.
      final queueRow = find.byKey(
        const ValueKey('void-settings-status-queue'),
        skipOffstage: false,
      );
      expect(queueRow, findsOneWidget);

      // The value column on a row contains a "3 tracks" string when length is 3.
      expect(
        find.descendant(
          of: queueRow,
          matching: find.text('3 tracks'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'shuffle toggle reflects provider state and tapping calls correct method',
      (tester) async {
        SettingsService().operatingModeNotifier.value = OperatingMode.own;
        final provider = _StubAudioProvider(
          queue: const [
            AudioTrack(path: '/a.mp3', title: 'a'),
            AudioTrack(path: '/b.mp3', title: 'b'),
          ],
          shuffle: false,
        );

        await _pumpInTallViewport(
          tester,
          _wrap(
            ChangeNotifierProvider<PlaybackController>.value(
              value: provider,
              child: const VoidSettingsSheet(),
            ),
          ),
        );

        final shuffleRow = find.byKey(
          const ValueKey('void-settings-status-shuffle'),
          skipOffstage: false,
        );
        expect(shuffleRow, findsOneWidget);

        // Initial state: off, no calls.
        expect(
          find.descendant(of: shuffleRow, matching: find.text('off')),
          findsOneWidget,
        );
        expect(provider.shuffleCalls, 0);
        expect(provider.disableCalls, 0);

        // Tap to enable shuffle.
        await tester.tap(shuffleRow);
        await tester.pump();

        expect(provider.shuffleCalls, 1);
        expect(provider.disableCalls, 0);

        // Re-render with shuffle on → label flips to "on".
        provider.setShuffle(true);
        await tester.pump();
        expect(
          find.descendant(of: shuffleRow, matching: find.text('on')),
          findsOneWidget,
        );

        // Tap again to disable.
        await tester.tap(shuffleRow);
        await tester.pump();

        expect(provider.shuffleCalls, 1);
        expect(provider.disableCalls, 1);
      },
    );

    testWidgets(
        'dot screen exposes show-song-info toggle that persists the flip (B-020)',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.own;
      // Force the active screen to dot so the DISPLAY group renders the
      // Dot rows (which now include the show-song-info toggle).
      await SettingsService().saveScreenConfig(const DotScreenConfig());

      await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

      final toggleFinder = find.byKey(
        const ValueKey('void-settings-dot-show-song-info'),
        skipOffstage: false,
      );
      expect(toggleFinder, findsOneWidget);

      // Initial state: off (DotScreenConfig default).
      final initialCfg =
          SettingsService().screenConfigNotifier.value as DotScreenConfig;
      expect(initialCfg.showSongInfo, isFalse);

      await tester.tap(toggleFinder);
      await tester.pump();

      final updatedCfg =
          SettingsService().screenConfigNotifier.value as DotScreenConfig;
      expect(updatedCfg.showSongInfo, isTrue);
    });

    // -------------------------------------------------------------------------
    // B-034 — SOUND visualizer rows gated on active hero's usesVisualizer
    // -------------------------------------------------------------------------
    group('B-034 — SOUND visualizer-row gating', () {
      const visualizerRowKeys = <String>[
        'void-settings-bar-count',
        'void-settings-bar-style',
        'void-settings-decay-speed',
        'void-settings-visualizer-color',
      ];

      Future<void> pumpWithScreen(
        WidgetTester tester,
        ScreenConfig cfg,
      ) async {
        SettingsService().operatingModeNotifier.value = OperatingMode.own;
        await SettingsService().saveScreenConfig(cfg);
        await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));
      }

      testWidgets('spectrum: all four visualizer rows are present',
          (tester) async {
        await pumpWithScreen(tester, const SpectrumScreenConfig());
        for (final k in visualizerRowKeys) {
          expect(
            find.byKey(ValueKey(k), skipOffstage: false),
            findsOneWidget,
            reason: '$k must be visible on spectrum',
          );
        }
        // The eq placeholder always stays.
        expect(
          find.byKey(const ValueKey('void-settings-eq'), skipOffstage: false),
          findsOneWidget,
        );
      });

      testWidgets('polo: all four visualizer rows are present',
          (tester) async {
        await pumpWithScreen(tester, const PoloScreenConfig());
        for (final k in visualizerRowKeys) {
          expect(
            find.byKey(ValueKey(k), skipOffstage: false),
            findsOneWidget,
            reason: '$k must be visible on polo',
          );
        }
      });

      testWidgets('dot: visualizer rows are hidden, eq stays',
          (tester) async {
        await pumpWithScreen(tester, const DotScreenConfig());
        for (final k in visualizerRowKeys) {
          expect(
            find.byKey(ValueKey(k), skipOffstage: false),
            findsNothing,
            reason: '$k must NOT be visible on dot',
          );
        }
        expect(
          find.byKey(const ValueKey('void-settings-eq'), skipOffstage: false),
          findsOneWidget,
        );
      });

      testWidgets('void: visualizer rows are hidden, eq stays',
          (tester) async {
        await pumpWithScreen(tester, const VoidScreenConfig());
        for (final k in visualizerRowKeys) {
          expect(
            find.byKey(ValueKey(k), skipOffstage: false),
            findsNothing,
            reason: '$k must NOT be visible on void',
          );
        }
        expect(
          find.byKey(const ValueKey('void-settings-eq'), skipOffstage: false),
          findsOneWidget,
        );
      });
    });

    // -------------------------------------------------------------------------
    // B-035 — text-size sliders on Dot and Void DISPLAY group
    // -------------------------------------------------------------------------
    group('B-035 — text-size slider in DISPLAY group', () {
      testWidgets('dot screen exposes the void-settings-dot-text-size slider',
          (tester) async {
        SettingsService().operatingModeNotifier.value = OperatingMode.own;
        await SettingsService().saveScreenConfig(const DotScreenConfig());

        await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

        expect(
          find.byKey(
            const ValueKey('void-settings-dot-text-size'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      });

      testWidgets('void screen exposes the void-settings-void-text-size slider',
          (tester) async {
        SettingsService().operatingModeNotifier.value = OperatingMode.own;
        await SettingsService().saveScreenConfig(const VoidScreenConfig());

        await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

        expect(
          find.byKey(
            const ValueKey('void-settings-void-text-size'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      });

      // B-041 — every screen exposes a text-size control, including Polo
      // (whose LCD font is bespoke). The old "no options" placeholder is gone.
      testWidgets('polo screen exposes the void-settings-polo-text-size slider',
          (tester) async {
        SettingsService().operatingModeNotifier.value = OperatingMode.own;
        await SettingsService().saveScreenConfig(const PoloScreenConfig());

        await _pumpInTallViewport(tester, _wrap(const VoidSettingsSheet()));

        expect(
          find.byKey(
            const ValueKey('void-settings-polo-text-size'),
            skipOffstage: false,
          ),
          findsOneWidget,
          reason: 'B-041: Polo must expose a text-size control like every '
              'other screen.',
        );
        expect(
          find.byKey(
            const ValueKey('void-settings-polo-display'),
            skipOffstage: false,
          ),
          findsNothing,
          reason: 'B-041: the old Polo "no options" placeholder is replaced '
              'by the text-size slider.',
        );
      });
    });

    testWidgets('status strip hides when queue is empty',
        (tester) async {
      SettingsService().operatingModeNotifier.value = OperatingMode.own;
      final provider = _StubAudioProvider(
        queue: const <AudioTrack>[],
        shuffle: false,
      );

      await _pumpInTallViewport(
        tester,
        _wrap(
          ChangeNotifierProvider<PlaybackController>.value(
            value: provider,
            child: const VoidSettingsSheet(),
          ),
        ),
      );

      expect(
        find.byKey(
          const ValueKey('void-settings-status-queue'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('void-settings-status-shuffle'),
          skipOffstage: false,
        ),
        findsNothing,
      );
    });
  });
}

/// Minimal PlaybackController stub that exposes a controllable queue + shuffle
/// state and counts calls to the shuffle/disable shuffle entry points.
class _StubAudioProvider extends PlaybackController {
  _StubAudioProvider({
    required List<AudioTrack> queue,
    required bool shuffle,
  })  : _queueOverride = queue,
        _shuffleOverride = shuffle,
        super(transport: MockAudioTransport());

  List<AudioTrack> _queueOverride;
  bool _shuffleOverride;
  int shuffleCalls = 0;
  int disableCalls = 0;

  @override
  List<AudioTrack> get queue => _queueOverride;

  @override
  bool get shuffle => _shuffleOverride;

  void setShuffle(bool value) {
    _shuffleOverride = value;
    notifyListeners();
  }

  void setQueueTracks(List<AudioTrack> tracks) {
    _queueOverride = tracks;
    notifyListeners();
  }

  @override
  Future<void> shuffleQueue() async {
    shuffleCalls += 1;
  }

  @override
  Future<void> disableShuffle() async {
    disableCalls += 1;
  }
}
