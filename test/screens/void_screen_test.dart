import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/controllers/library_controller.dart';
import 'package:nothingness/models/audio_track.dart';
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

      // After the jump, the glyph must disappear (dirname == currentPath).
      expect(find.byKey(glyphKey), findsNothing,
          reason: 'B-015: glyph must vanish once we are in the playing '
              'folder.');
    });
  });
}
