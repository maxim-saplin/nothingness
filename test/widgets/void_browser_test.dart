import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/controllers/library_controller.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/song_info.dart';
import 'package:nothingness/services/library_browser.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/widgets/press_feedback.dart';
import 'package:nothingness/widgets/void_browser.dart';
import 'package:provider/provider.dart';

import 'heroes/_test_helpers.dart';

/// Test seam: a LibraryController that publishes a preset list of tracks
/// without touching the real filesystem or MediaStore.
class _FakeLibraryController extends LibraryController {
  _FakeLibraryController({
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall methodCall) async => null,
  );

  group('B-015: VoidBrowser.scrollToTrack', () {
    testWidgets(
        'scrolls the now-playing row into view (on-screen after the call)',
        (tester) async {
      // Use a small list that fits entirely in the viewport so every row's
      // RenderObject is laid out — exercises the key plumbing and the
      // ensureVisible call without depending on Sliver lazy-build behaviour.
      // The off-viewport scrolling path is covered by the live smoke test.
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tracks = List<AudioTrack>.generate(
        5,
        (i) => AudioTrack(
          path: '/lib/folder/track_$i.mp3',
          title: 'Track $i',
        ),
      );
      final targetPath = tracks.first.path;

      final controller = _FakeLibraryController(
        currentPath: '/lib/folder',
        tracks: tracks,
      );

      final provider = FakeAudioPlayerProvider(
        songInfo: SongInfo(
          track: AudioTrack(path: targetPath, title: 'Track 0'),
          isPlaying: true,
          position: 0,
          duration: 1000,
        ),
      );

      final browserKey = GlobalKey<VoidBrowserState>();

      await tester.pumpWidget(
        wrapWithProvider(
          provider,
          ChangeNotifierProvider<LibraryController>.value(
            value: controller,
            child: SizedBox(
              height: 600,
              child: VoidBrowser(key: browserKey, controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rowFinder = find.byKey(const ValueKey('void-file:/lib/folder/track_0.mp3'));
      expect(rowFinder, findsOneWidget,
          reason: 'B-015: row must be built with a stable key.');

      await browserKey.currentState!.scrollToTrack(targetPath);
      await tester.pumpAndSettle();

      final box = tester.renderObject<RenderBox>(rowFinder);
      final topLeft = box.localToGlobal(Offset.zero);
      final size = box.size;
      expect(topLeft.dy + size.height, greaterThanOrEqualTo(0),
          reason: 'B-015: scrolled row must be on or below the viewport top.');
      expect(topLeft.dy, lessThanOrEqualTo(600),
          reason: 'B-015: scrolled row must be on or above the viewport bottom.');
    });

    testWidgets(
        'reverse:true list centers via alignment=0.5 — target row lands near '
        'the vertical mid-line of the viewport', (tester) async {
      // Tall viewport, lots of small visible rows so scroll has real travel.
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // A list big enough to require scrolling but small enough that every
      // row is materialised by the time we ask for ensureVisible.
      // Row height is the geometry minimum (~56 px) — 12 rows = ~672 px, so
      // the top of the list scrolls off-screen.
      final tracks = List<AudioTrack>.generate(
        12,
        (i) => AudioTrack(
          path: '/lib/folder/t_${i.toString().padLeft(2, '0')}.mp3',
          title: 't$i',
        ),
      );
      final targetPath = tracks[6].path; // middle of the list

      final controller = _FakeLibraryController(
        currentPath: '/lib/folder',
        tracks: tracks,
      );
      final provider = FakeAudioPlayerProvider(
        songInfo: SongInfo(
          track: AudioTrack(path: targetPath, title: 't6'),
          isPlaying: true,
          position: 0,
          duration: 1000,
        ),
      );

      final browserKey = GlobalKey<VoidBrowserState>();

      await tester.pumpWidget(
        wrapWithProvider(
          provider,
          ChangeNotifierProvider<LibraryController>.value(
            value: controller,
            child: SizedBox(
              height: 600,
              child: VoidBrowser(key: browserKey, controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await browserKey.currentState!.scrollToTrack(targetPath);
      await tester.pumpAndSettle();

      final rowFinder = find.byKey(const ValueKey('void-file:/lib/folder/t_06.mp3'));
      expect(rowFinder, findsOneWidget,
          reason: 'B-015: target row must be present after ensureVisible.');
      final box = tester.renderObject<RenderBox>(rowFinder);
      final centerY = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
      // Centering should land the row within the middle ~half of the
      // viewport — the precise pixel depends on row height & padding but
      // an alignment of 0.5 must keep it well clear of the edges, even
      // with reverse:true flipping the axis direction.
      expect(centerY, inInclusiveRange(150.0, 450.0),
          reason: 'B-015: alignment=0.5 must land the row near the vertical '
              'center even on a reverse:true list.');
    });
  });

  group('B-030: VoidBrowser press feedback', () {
    testWidgets(
        'file rows are wrapped in PressFeedback and dip opacity on touch-down',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tracks = <AudioTrack>[
        const AudioTrack(path: '/lib/folder/a.mp3', title: 'A'),
        const AudioTrack(path: '/lib/folder/b.mp3', title: 'B'),
      ];
      final controller = _FakeLibraryController(
        currentPath: '/lib/folder',
        tracks: tracks,
      );
      final provider = FakeAudioPlayerProvider();

      await tester.pumpWidget(
        wrapWithProvider(
          provider,
          ChangeNotifierProvider<LibraryController>.value(
            value: controller,
            child: SizedBox(
              height: 600,
              child: VoidBrowser(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Adoption: every browser row sits under a PressFeedback wrapper.
      expect(find.byType(PressFeedback), findsAtLeastNWidgets(tracks.length));

      // Press dip: target a known row by ValueKey and verify the embedded
      // AnimatedOpacity flips to PressFeedback.pressedOpacity on touch-down.
      final rowFinder = find.byKey(const ValueKey('void-file:/lib/folder/a.mp3'));
      expect(rowFinder, findsOneWidget);
      final opacityFinder = find.descendant(
        of: rowFinder,
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1.0);

      final gesture =
          await tester.startGesture(tester.getCenter(rowFinder));
      // _VoidRow registers a long-press handler, so the GestureDetector
      // arena waits past kPressTimeout (100 ms) before firing onTapDown.
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester.widget<AnimatedOpacity>(opacityFinder).opacity,
        PressFeedback.pressedOpacity,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
