import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/controllers/library_controller.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/browser_presentation.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/song_info.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/models/transport_position.dart';
import 'package:nothingness/screens/void_screen.dart';
import 'package:nothingness/services/library_browser.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:nothingness/theme/app_typography.dart';
import 'package:nothingness/widgets/heroes/dot_hero.dart';
import 'package:nothingness/widgets/heroes/polo_hero.dart';
import 'package:nothingness/widgets/heroes/spectrum_hero.dart';
import 'package:nothingness/widgets/heroes/void_hero.dart';
import 'package:nothingness/widgets/press_feedback.dart';
import 'package:nothingness/widgets/transport_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/heroes/_test_helpers.dart';

Future<void> _pump(
  WidgetTester tester,
  ScreenConfig config, {
  FakeAudioPlayerProvider? provider,
  LibraryController? libraryController,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final p = provider ?? FakeAudioPlayerProvider();
  await tester.pumpWidget(
    wrapWithProvider(
      p,
      VoidScreen(
        config: config,
        settings: const SpectrumSettings(),
        libraryController: libraryController,
      ),
    ),
  );
  await tester.pump();
}

/// Test seam for B-015: a LibraryController that publishes a preset
/// `currentPath` + `tracks` without touching the real filesystem, and
/// records calls to `loadFolder`.
class _RecordingLibraryController extends LibraryController {
  _RecordingLibraryController({
    String? currentPath,
    List<AudioTrack> tracks = const <AudioTrack>[],
  }) : super(
          libraryBrowser: LibraryBrowser(supportedExtensions: const {'mp3'}),
          libraryService: LibraryService(),
          isAndroidOverride: false,
        ) {
    this.currentPath = currentPath;
    this.tracks = List<AudioTrack>.from(tracks);
    hasPermission = true;
  }

  final List<String> loadFolderCalls = <String>[];

  @override
  Future<void> loadFolder(String path) async {
    loadFolderCalls.add(path);
    currentPath = path;
    notifyListeners();
  }
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
    SettingsService().transportPositionNotifier.value =
        TransportPosition.bottom;
    SettingsService().browserPresentationNotifier.value =
        SettingsService.defaultBrowserPresentation;
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

  group('B-018: per-skin transport contract', () {
    test('hostsChromeTransport: hosted heroes true, Polo false', () {
      expect(const VoidScreenConfig().hostsChromeTransport, isTrue,
          reason: 'B-018: Void hero hosts the chrome transport row.');
      expect(const SpectrumScreenConfig().hostsChromeTransport, isTrue,
          reason: 'B-018: Spectrum hero hosts the chrome transport row.');
      expect(const DotScreenConfig().hostsChromeTransport, isTrue,
          reason: 'B-018: Dot hero hosts the chrome transport row.');
      expect(const PoloScreenConfig().hostsChromeTransport, isFalse,
          reason:
              'B-018: Polo is bespoke — the shell must NOT paint a chrome '
              'transport row over Polo.');
    });

    testWidgets(
        'transport=bottom: Spectrum (hosted) gets hero band == total - '
        'transport row height', (tester) async {
      SettingsService().transportPositionNotifier.value =
          TransportPosition.bottom;
      await _pump(tester, const SpectrumScreenConfig());

      // Locate the rendered TransportRow and SpectrumHero render boxes;
      // the SpectrumHero band should occupy the area above the transport
      // (i.e. its height should equal screen height - transport height,
      // give or take the crumb / hairline slots which are below the
      // transport when position == bottom).
      final transportFinder = find.byType(TransportRow);
      final heroFinder = find.byType(SpectrumHero);
      expect(transportFinder, findsOneWidget);
      expect(heroFinder, findsOneWidget);

      final transportBox =
          tester.renderObject<RenderBox>(transportFinder);
      final heroBox = tester.renderObject<RenderBox>(heroFinder);
      final transportTop =
          transportBox.localToGlobal(Offset.zero).dy;
      final heroBottom =
          heroBox.localToGlobal(Offset(0, heroBox.size.height)).dy;
      // The hero band must end at (or above) the transport row's top edge
      // — heroes never paint behind the transport row.
      expect(heroBottom, lessThanOrEqualTo(transportTop + 0.5),
          reason: 'B-018: hosted hero band must end at the transport row.');
    });

    testWidgets(
        'transport=off: hosted heroes get the full hero area, no '
        'TransportRow painted', (tester) async {
      SettingsService().transportPositionNotifier.value =
          TransportPosition.off;
      await _pump(tester, const SpectrumScreenConfig());

      expect(find.byType(TransportRow), findsNothing,
          reason:
              'B-018: with transport=off, the chrome must not paint a row.');
      // The hero should be present and its height should exceed the prior
      // (bottom) layout's hero band — i.e. there is no transport carve-out.
      final heroFinder = find.byType(SpectrumHero);
      expect(heroFinder, findsOneWidget);
      final heroBox = tester.renderObject<RenderBox>(heroFinder);
      expect(heroBox.size.height, greaterThan(0));
    });

    testWidgets(
        'Polo with transport=bottom: shell does NOT paint TransportRow',
        (tester) async {
      SettingsService().transportPositionNotifier.value =
          TransportPosition.bottom;
      await _pump(tester, const PoloScreenConfig());

      expect(find.byType(PoloHero), findsOneWidget);
      expect(find.byType(TransportRow), findsNothing,
          reason: 'B-018: Polo is bespoke — chrome transport row must be '
              'suppressed regardless of the global transport setting.');
    });

    testWidgets(
        'Polo with transport=top: shell does NOT paint TransportRow',
        (tester) async {
      SettingsService().transportPositionNotifier.value =
          TransportPosition.top;
      await _pump(tester, const PoloScreenConfig());

      expect(find.byType(PoloHero), findsOneWidget);
      expect(find.byType(TransportRow), findsNothing,
          reason: 'B-018: Polo stays bespoke under transport=top too.');
    });
  });

  group('B-015: crumb jump-to-now-playing glyph', () {
    const glyphKey = ValueKey('void-crumb-jump-to-playing');

    testWidgets('hidden when nothing is playing', (tester) async {
      final controller = _RecordingLibraryController(
        currentPath: '/lib/Indie',
        tracks: const <AudioTrack>[],
      );
      await _pump(tester, const SpectrumScreenConfig(),
          libraryController: controller);
      expect(find.byKey(glyphKey), findsNothing,
          reason:
              'B-015: glyph must be hidden when there is no song to jump to.');
    });

    testWidgets(
        'hidden when dirname(playing) == currentPath (already in the folder)',
        (tester) async {
      final controller = _RecordingLibraryController(
        currentPath: '/lib/Indie',
        tracks: const <AudioTrack>[],
      );
      final provider = FakeAudioPlayerProvider(
        songInfo: SongInfo(
          track: const AudioTrack(
            path: '/lib/Indie/wake_up.mp3',
            title: 'Wake Up',
          ),
          isPlaying: true,
          position: 0,
          duration: 1000,
        ),
      );
      await _pump(tester, const SpectrumScreenConfig(),
          provider: provider, libraryController: controller);
      expect(find.byKey(glyphKey), findsNothing,
          reason:
              'B-015: glyph must be hidden when already in the playing folder.');
    });

    testWidgets('visible when dirname(playing) != currentPath',
        (tester) async {
      final controller = _RecordingLibraryController(
        currentPath: '/lib/Music',
        tracks: const <AudioTrack>[],
      );
      final provider = FakeAudioPlayerProvider(
        songInfo: SongInfo(
          track: const AudioTrack(
            path: '/lib/Music/Indie/wake_up.mp3',
            title: 'Wake Up',
          ),
          isPlaying: true,
          position: 0,
          duration: 1000,
        ),
      );
      await _pump(tester, const SpectrumScreenConfig(),
          provider: provider, libraryController: controller);

      final glyph = find.byKey(glyphKey);
      expect(glyph, findsOneWidget,
          reason:
              'B-015: glyph must be visible when playing track is in a '
              'different folder.');

      // 44x44 hit target per Material guideline (matches B-013 pattern).
      final box = tester.renderObject<RenderBox>(glyph);
      expect(box.size.width, greaterThanOrEqualTo(44.0),
          reason: 'B-015: hit target width must be >= 44px.');
      expect(box.size.height, greaterThanOrEqualTo(44.0),
          reason: 'B-015: hit target height must be >= 44px.');
    });

    testWidgets(
        'tapping the glyph calls loadFolder(dirname(playing-track-path))',
        (tester) async {
      final controller = _RecordingLibraryController(
        currentPath: '/lib/Music',
        tracks: const <AudioTrack>[],
      );
      final provider = FakeAudioPlayerProvider(
        songInfo: SongInfo(
          track: const AudioTrack(
            path: '/lib/Music/Indie/wake_up.mp3',
            title: 'Wake Up',
          ),
          isPlaying: true,
          position: 0,
          duration: 1000,
        ),
      );
      await _pump(tester, const SpectrumScreenConfig(),
          provider: provider, libraryController: controller);

      await tester.tap(find.byKey(glyphKey));
      await tester.pumpAndSettle();

      expect(controller.loadFolderCalls, contains('/lib/Music/Indie'),
          reason: 'B-015: tap must navigate to the playing track\'s '
              'parent folder.');

      // After the jump, the glyph must eventually disappear (dirname ==
      // currentPath). B-031 added a 200ms hide-only debounce so the glyph
      // only vanishes after the predicate has been false continuously past
      // the window — pump past it.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(glyphKey), findsNothing,
          reason: 'B-015: glyph must vanish once we are in the playing '
              'folder (after B-031 debounce window).');
    });
  });

  group('B-027: hero swipe velocity escape', () {
    // The hero band sits at the top of the screen — pick a point well inside
    // it for our flings. MaterialApp's MediaQuery is driven by the engine
    // window (not setSurfaceSize), so the hero ends up ~192 px tall in
    // widget tests. y=80 is safely inside that band.
    const Offset heroPoint = Offset(400, 80);

    testWidgets('slow short swipe (<60 dp, low velocity) does NOT fire',
        (tester) async {
      final provider = _RecordingTransportProvider();
      await _pump(tester, const SpectrumScreenConfig(), provider: provider);

      // 40 px over 800 ms ≈ 50 px/s — well under the 300 px/s threshold.
      await tester.timedDragFrom(
        heroPoint,
        const Offset(40, 0),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();

      expect(provider.nextCalls, 0,
          reason: 'B-027: slow short swipe must not fire next.');
      expect(provider.previousCalls, 0,
          reason: 'B-027: slow short swipe must not fire previous.');
    });

    testWidgets('slow long swipe (>60 dp) still fires (distance threshold)',
        (tester) async {
      final provider = _RecordingTransportProvider();
      await _pump(tester, const SpectrumScreenConfig(), provider: provider);

      // 200 px over 1500 ms ≈ 130 px/s. Velocity is well under 300 px/s,
      // but distance crosses 60 dp, so the existing accumulator must fire.
      await tester.timedDragFrom(
        heroPoint,
        const Offset(200, 0),
        const Duration(milliseconds: 1500),
      );
      await tester.pumpAndSettle();

      expect(provider.nextCalls, greaterThanOrEqualTo(1),
          reason: 'B-027: long slow rightward swipe must fire next '
              '(existing 60-dp accumulator behaviour preserved).');
      expect(provider.previousCalls, 0);
    });

    testWidgets('fast short flick (<60 dp, high velocity) FIRES — rightward',
        (tester) async {
      final provider = _RecordingTransportProvider();
      await _pump(tester, const SpectrumScreenConfig(), provider: provider);

      // 50 px at 800 px/s — distance under 60 dp, velocity over 300 px/s.
      await tester.flingFrom(
        heroPoint,
        const Offset(50, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(provider.nextCalls, 1,
          reason: 'B-027: fast short rightward flick must fire next via '
              'the velocity escape, even when distance is under 60 dp.');
      expect(provider.previousCalls, 0);
    });

    testWidgets('fast short flick (<60 dp, high velocity) FIRES — leftward',
        (tester) async {
      final provider = _RecordingTransportProvider();
      await _pump(tester, const SpectrumScreenConfig(), provider: provider);

      await tester.flingFrom(
        heroPoint,
        const Offset(-50, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(provider.previousCalls, 1,
          reason: 'B-027: fast short leftward flick must fire previous via '
              'the velocity escape; direction = sign of velocity.');
      expect(provider.nextCalls, 0);
    });

    testWidgets('low-velocity short swipe (<60 dp, <300 px/s) does NOT fire',
        (tester) async {
      final provider = _RecordingTransportProvider();
      await _pump(tester, const SpectrumScreenConfig(), provider: provider);

      // 50 px at 100 px/s — both distance and velocity under their
      // thresholds, so neither branch should fire.
      await tester.flingFrom(
        heroPoint,
        const Offset(50, 0),
        100,
      );
      await tester.pumpAndSettle();

      expect(provider.nextCalls, 0,
          reason: 'B-027: velocity below ~300 px/s threshold must not fire.');
      expect(provider.previousCalls, 0);
    });

    testWidgets('velocity escape does not double-fire after distance trip',
        (tester) async {
      final provider = _RecordingTransportProvider();
      await _pump(tester, const SpectrumScreenConfig(), provider: provider);

      // 80 px at 800 px/s — distance crosses 60 dp exactly once during the
      // drag (accumulator resets after firing, then has only 20 px left, so
      // no second distance trip). End velocity is ~800 px/s, well over the
      // 300 px/s velocity threshold. With the fired-guard in place the
      // gesture must still produce exactly one next() — not two.
      await tester.flingFrom(
        heroPoint,
        const Offset(80, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(provider.nextCalls, 1,
          reason: 'B-027: when a single drag both trips distance AND ends '
              'above the velocity threshold, the velocity escape must NOT '
              're-fire — exactly one transport event per gesture.');
      expect(provider.previousCalls, 0);
    });
  });

  _b031Tests();

  _b032Tests();

  group('B-030 follow-up: chrome tappables wear PressFeedback', () {
    testWidgets('settings ⋮ button has a PressFeedback ancestor',
        (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      final btn = find.byKey(const ValueKey('void-settings-button'));
      expect(btn, findsOneWidget);
      // The settings button itself is now a PressFeedback (the ValueKey is
      // attached to the PressFeedback), so find it directly.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('void-settings-button')),
          matching: find.byType(AnimatedOpacity),
        ),
        findsWidgets,
        reason: 'B-030 follow-up: settings ⋮ must wear PressFeedback so '
            'taps produce the universal touch-down dip.',
      );
      expect(tester.widget(btn), isA<PressFeedback>(),
          reason: 'B-030 follow-up: settings ⋮ must BE a PressFeedback (the '
              'ValueKey is hoisted onto it).');
    });

    testWidgets('swipe-up hint has a PressFeedback wrapping its onTap',
        (tester) async {
      // The hint is only rendered when the user has opted into the
      // swipe-up browser presentation (settings default is `fixed`).
      SettingsService().browserPresentationNotifier.value =
          BrowserPresentation.swipeUp;
      await _pump(tester, const SpectrumScreenConfig());
      final hint = find.text('↑ swipe to browse');
      expect(hint, findsOneWidget,
          reason: 'B-030 follow-up: swipe-up hint must be rendered with '
              'BrowserPresentation.swipeUp and the browser collapsed.');
      expect(
        find.ancestor(of: hint, matching: find.byType(PressFeedback)),
        findsOneWidget,
        reason: 'B-030 follow-up: the swipe-up hint\'s tap target must be '
            'wrapped in PressFeedback so the tap dips its opacity.',
      );
    });
  });
}

/// Records calls to `next()` / `previous()` so B-027 tests can assert which
/// transport action a swipe / flick produced. Inherits the rest of the
/// player surface from [FakeAudioPlayerProvider].
class _RecordingTransportProvider extends FakeAudioPlayerProvider {
  int nextCalls = 0;
  int previousCalls = 0;

  @override
  Future<void> next() async {
    nextCalls++;
  }

  @override
  Future<void> previous() async {
    previousCalls++;
  }
}

// ---------------------------------------------------------------------------
// B-031 helpers + tests
// ---------------------------------------------------------------------------

/// Test seam for B-031: extends the recording controller with a settable
/// path-only `notifyListeners()` hook so tests can simulate a transient race
/// between `library.currentPath` and `playback.songInfo`.
class _B031Controller extends _RecordingLibraryController {
  _B031Controller({
    super.currentPath,
    super.tracks,
  });

  /// Imperatively update `currentPath` and fan out a notification — the
  /// LibraryController listener inside [VoidScreen] rebuilds the crumb.
  void simulatePathChange(String? next) {
    currentPath = next;
    notifyListeners();
  }
}

void _b031Tests() {
  group('B-031: jump-to-now-playing reliability', () {
    const glyphKey = ValueKey('void-crumb-jump-to-playing');

    testWidgets(
      'glyph stays visible during a transient currentPath==dirname flip (<200ms)',
      (tester) async {
        // Start with a configuration where the glyph SHOULD be visible
        // (currentPath != dirname of the playing track).
        final controller = _B031Controller(
          currentPath: '/lib/Music',
          tracks: const <AudioTrack>[],
        );
        final provider = FakeAudioPlayerProvider(
          songInfo: SongInfo(
            track: const AudioTrack(
              path: '/lib/Music/Indie/wake_up.mp3',
              title: 'Wake Up',
            ),
            isPlaying: true,
            position: 0,
            duration: 1000,
          ),
        );
        await _pump(tester, const SpectrumScreenConfig(),
            provider: provider, libraryController: controller);

        expect(find.byKey(glyphKey), findsOneWidget,
            reason: 'B-031: precondition — glyph visible at start.');

        // Simulate a brief race: currentPath flips to the playing folder for
        // ~50ms. Without debounce the glyph would IMMEDIATELY disappear at
        // this point because `dirname(playingPath) == currentPath`. With
        // B-031's debounce it must stay visible during the window.
        controller.simulatePathChange('/lib/Music/Indie');
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(glyphKey), findsOneWidget,
            reason: 'B-031: glyph must NOT hide on a <200ms transient flip '
                'between currentPath and songInfo updates.');

        // Flip back BEFORE the 200ms window closes. The debounce timer should
        // have nothing to do — the next-frame predicate is true again.
        controller.simulatePathChange('/lib/Music');
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(glyphKey), findsOneWidget,
            reason: 'B-031: glyph must still be visible after the race '
                'resolves back to the divergent state.');
      },
    );

    testWidgets('glyph hides if currentPath==dirname persists past 200ms',
        (tester) async {
      final controller = _B031Controller(
        currentPath: '/lib/Music',
        tracks: const <AudioTrack>[],
      );
      final provider = FakeAudioPlayerProvider(
        songInfo: SongInfo(
          track: const AudioTrack(
            path: '/lib/Music/Indie/wake_up.mp3',
            title: 'Wake Up',
          ),
          isPlaying: true,
          position: 0,
          duration: 1000,
        ),
      );
      await _pump(tester, const SpectrumScreenConfig(),
          provider: provider, libraryController: controller);

      expect(find.byKey(glyphKey), findsOneWidget,
          reason: 'B-031: precondition — glyph visible at start.');

      // Flip to the playing folder and stay there past the debounce window.
      controller.simulatePathChange('/lib/Music/Indie');
      await tester.pump();
      // Let the debounce timer fire.
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(glyphKey), findsNothing,
          reason: 'B-031: glyph must hide once the dirname match persists '
              'past ~200ms.');
    });

    testWidgets(
      'tap on glyph opens the swipe-up browser when it is dismissed',
      (tester) async {
        SettingsService().browserPresentationNotifier.value =
            BrowserPresentation.swipeUp;
        addTearDown(() {
          SettingsService().browserPresentationNotifier.value =
              SettingsService.defaultBrowserPresentation;
        });

        final controller = _B031Controller(
          currentPath: '/lib/Music',
          tracks: const <AudioTrack>[
            AudioTrack(
                path: '/lib/Music/Indie/wake_up.mp3', title: 'Wake Up'),
          ],
        );
        final provider = FakeAudioPlayerProvider(
          songInfo: SongInfo(
            track: const AudioTrack(
              path: '/lib/Music/Indie/wake_up.mp3',
              title: 'Wake Up',
            ),
            isPlaying: true,
            position: 0,
            duration: 1000,
          ),
        );
        await _pump(tester, const SpectrumScreenConfig(),
            provider: provider, libraryController: controller);

        // Browser is collapsed in swipe-up presentation by default — the
        // hint band is rendered, the VoidBrowser is NOT mounted.
        expect(find.text('↑ swipe to browse'), findsOneWidget,
            reason: 'B-031: precondition — browser is in swipe-up dismissed '
                'state at the start of the test.');

        await tester.tap(find.byKey(glyphKey));
        // Pump through the open animation (~250ms) and any subsequent
        // loadFolder / scroll work.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // After the jump, the browser must be visible (open path triggered)
        // — the hint band is replaced by the VoidBrowser.
        expect(find.text('↑ swipe to browse'), findsNothing,
            reason: 'B-031: tapping the glyph while the swipe-up browser is '
                'dismissed must trigger the open path.');
      },
    );

    testWidgets(
      'tap on glyph does NOT toggle browser state when it is already visible',
      (tester) async {
        // Fixed presentation — browser is always visible, no open/close
        // state to flip. The jump action must NOT change presentation state.
        SettingsService().browserPresentationNotifier.value =
            BrowserPresentation.fixed;

        final controller = _B031Controller(
          currentPath: '/lib/Music',
          tracks: const <AudioTrack>[
            AudioTrack(
                path: '/lib/Music/Indie/wake_up.mp3', title: 'Wake Up'),
          ],
        );
        final provider = FakeAudioPlayerProvider(
          songInfo: SongInfo(
            track: const AudioTrack(
              path: '/lib/Music/Indie/wake_up.mp3',
              title: 'Wake Up',
            ),
            isPlaying: true,
            position: 0,
            duration: 1000,
          ),
        );
        await _pump(tester, const SpectrumScreenConfig(),
            provider: provider, libraryController: controller);

        // The swipe-up hint band MUST not be present in fixed presentation.
        expect(find.text('↑ swipe to browse'), findsNothing,
            reason: 'B-031: precondition — fixed presentation never paints '
                'the swipe-up hint.');

        await tester.tap(find.byKey(glyphKey));
        await tester.pumpAndSettle();

        // After the jump the browser must STILL be visible (no spurious
        // collapse) and the swipe-up hint band must STILL be absent.
        expect(find.text('↑ swipe to browse'), findsNothing,
            reason: 'B-031: tap on glyph in fixed presentation must not '
                'toggle browser state.');
      },
    );
  });
}

// ---------------------------------------------------------------------------
// B-032 tests — drag-down-to-close affordance on the open browser.
// ---------------------------------------------------------------------------

/// Helper: open the swipe-up browser via the hint band tap so each B-032 test
/// starts from the canonical "browser expanded" state.
Future<void> _openSwipeUpBrowser(WidgetTester tester) async {
  expect(find.text('↑ swipe to browse'), findsOneWidget,
      reason: 'B-032: precondition — hint band visible before opening.');
  await tester.tap(find.text('↑ swipe to browse'));
  await tester.pumpAndSettle();
  expect(find.text('↑ swipe to browse'), findsNothing,
      reason: 'B-032: browser must be open after the hint tap.');
}

void _b032Tests() {
  group('B-032: drag-down-to-close', () {
    const handleKey = ValueKey('void-browser-drag-handle');
    const closeGestureKey = ValueKey('void-browser-close-drag-region');

    setUp(() {
      SettingsService().browserPresentationNotifier.value =
          BrowserPresentation.swipeUp;
    });

    tearDown(() {
      SettingsService().browserPresentationNotifier.value =
          SettingsService.defaultBrowserPresentation;
    });

    testWidgets('drag handle visible only after the browser opens',
        (tester) async {
      await _pump(tester, const SpectrumScreenConfig());

      // Closed (hint band visible) — handle absent.
      expect(find.byKey(handleKey), findsNothing,
          reason: 'B-032: handle must NOT render when the browser is closed.');

      await _openSwipeUpBrowser(tester);

      // After open, handle must be on screen.
      expect(find.byKey(handleKey), findsOneWidget,
          reason: 'B-032: handle must render once the browser is open in '
              'swipe-up presentation.');
    });

    testWidgets('drag DOWN > 60 dp on the handle closes the browser',
        (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      await _openSwipeUpBrowser(tester);

      final regionFinder = find.byKey(closeGestureKey);
      expect(regionFinder, findsOneWidget,
          reason: 'B-032: close-drag region must be present once expanded.');

      // Slow long drag: 120 dp over 1500 ms → ~80 px/s velocity (below the
      // 300 px/s threshold). Exercises the DISTANCE branch of the dual
      // threshold.
      await tester.timedDragFrom(
        tester.getCenter(regionFinder),
        const Offset(0, 120),
        const Duration(milliseconds: 1500),
      );
      await tester.pumpAndSettle();

      expect(find.text('↑ swipe to browse'), findsOneWidget,
          reason: 'B-032: distance-threshold drag DOWN on the handle '
              'region must close the browser.');
    });

    testWidgets('fast short flick DOWN (<60 dp, >300 dp/s) closes the browser',
        (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      await _openSwipeUpBrowser(tester);

      final regionFinder = find.byKey(closeGestureKey);
      expect(regionFinder, findsOneWidget);

      // 50 px at 1500 px/s — distance under 60 dp, velocity well over the
      // 300 px/s threshold (4x). Exercises the VELOCITY branch of the dual
      // threshold.
      await tester.flingFrom(
        tester.getCenter(regionFinder),
        const Offset(0, 50),
        1500,
      );
      await tester.pumpAndSettle();

      expect(find.text('↑ swipe to browse'), findsOneWidget,
          reason: 'B-032: velocity-escape flick DOWN must close the browser.');
    });

    testWidgets('vertical drag UP (negative dy) does NOT close',
        (tester) async {
      await _pump(tester, const SpectrumScreenConfig());
      await _openSwipeUpBrowser(tester);

      final regionFinder = find.byKey(closeGestureKey);
      expect(regionFinder, findsOneWidget);

      // Long upward drag, well past 60 dp. Must NOT close — sign check.
      await tester.timedDragFrom(
        tester.getCenter(regionFinder),
        const Offset(0, -200),
        const Duration(milliseconds: 1500),
      );
      await tester.pumpAndSettle();

      expect(find.text('↑ swipe to browse'), findsNothing,
          reason: 'B-032: upward drag must NOT collapse the browser '
              '(sign check: only downward drags close).');
    });

    testWidgets('drag DOWN on the scrollable list does NOT close',
        (tester) async {
      final controller = _RecordingLibraryController(
        currentPath: '/lib/folder',
        tracks: List<AudioTrack>.generate(
          40,
          (i) => AudioTrack(
            path: '/lib/folder/track_${i.toString().padLeft(2, '0')}.mp3',
            title: 'Track $i',
          ),
        ),
      );
      await _pump(
        tester,
        const SpectrumScreenConfig(),
        libraryController: controller,
      );
      await _openSwipeUpBrowser(tester);

      // Drag down INSIDE the list area (a visible row). The list scrolls;
      // the browser must stay open.
      final rowFinder =
          find.byKey(const ValueKey('void-file:/lib/folder/track_00.mp3'));
      // Some rows may be off-screen depending on layout — pick any visible
      // row by querying the first PressFeedback inside the list.
      final firstRowFinder = rowFinder.evaluate().isNotEmpty
          ? rowFinder
          : find.byKey(
              const ValueKey('void-file:/lib/folder/track_39.mp3'),
            );
      expect(firstRowFinder, findsOneWidget,
          reason: 'B-032: precondition — at least one list row visible.');

      await tester.timedDragFrom(
        tester.getCenter(firstRowFinder),
        const Offset(0, 200),
        const Duration(milliseconds: 1500),
      );
      await tester.pumpAndSettle();

      expect(find.text('↑ swipe to browse'), findsNothing,
          reason: 'B-032: vertical drag inside the scrollable list region '
              'must NOT close the browser (list scrolls instead).');
    });

    testWidgets('fixed presentation: no drag handle, drag has no effect',
        (tester) async {
      SettingsService().browserPresentationNotifier.value =
          BrowserPresentation.fixed;
      await _pump(tester, const SpectrumScreenConfig());

      // Fixed presentation: browser always visible, hint band absent.
      expect(find.text('↑ swipe to browse'), findsNothing,
          reason: 'B-032: fixed presentation never paints the hint band.');
      expect(find.byKey(handleKey), findsNothing,
          reason: 'B-032: fixed presentation must NOT render the drag '
              'handle — the browser cannot be closed by drag in fixed mode.');
      expect(find.byKey(closeGestureKey), findsNothing,
          reason: 'B-032: fixed presentation must NOT wire the close '
              'gesture region.');
    });
  });
}
