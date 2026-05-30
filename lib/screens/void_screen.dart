import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../controllers/library_controller.dart';
import '../models/browser_presentation.dart';
import '../models/screen_config.dart';
import '../models/spectrum_settings.dart';
import '../models/transport_position.dart';
import '../providers/audio_player_provider.dart';
import '../services/library_browser.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../debug_hooks.dart';
import '../theme/app_geometry.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import '../widgets/hero_feedback_surface.dart';
import '../widgets/heroes/dot_hero.dart';
import '../widgets/heroes/polo_hero.dart';
import '../widgets/heroes/spectrum_hero.dart';
import '../widgets/heroes/void_hero.dart';
import '../widgets/mid_ellipsis.dart';
import '../widgets/press_feedback.dart';
import '../widgets/transport_row.dart';
import '../widgets/void_browser.dart';
import '../widgets/void_settings_sheet.dart';

// Fixed slot heights.
const double _crumbHeight = 56.0;
const double _transportHeight = TransportRow.transportHeight;
const double _swipeHintZoneHeight = 56.0;

// B-031: hide-only debounce for the crumb's ⊙ jump glyph — filters one-frame
// races where dirname(songInfo.path) briefly == currentPath on track changes.
const Duration _jumpGlyphHideDebounce = Duration(milliseconds: 200);
// Settle window after opening the browser so its first frame lays out before
// we navigate + scroll; ~250 ms reads as one gesture.
const Duration _browserOpenSettle = Duration(milliseconds: 250);

/// Home shell for all four visualisations: hero, embedded [VoidBrowser],
/// transport row, crumb (path / search), progress hairline. Hero tap-zones
/// (prev/play-pause/next) + drag-to-seek; immersive mode hides chrome.
class VoidScreen extends HookWidget {
  const VoidScreen({
    super.key,
    this.config,
    this.settings,
    this.libraryController,
  });

  /// Active config; falls back to [SettingsService.screenConfigNotifier] when null.
  final ScreenConfig? config;

  /// Spectrum settings forwarded to the spectrum hero.
  final SpectrumSettings? settings;

  /// Externally-owned controller; when supplied the screen neither creates nor
  /// disposes its own — used by tests to pre-seed currentPath/tracks (B-015).
  final LibraryController? libraryController;

  @override
  Widget build(BuildContext context) {
    final settingsService = useMemoized(() => SettingsService());

    // B-015: lets the crumb's jump tap drive scrollToTrack after loadFolder.
    final browserKey = useMemoized(() => GlobalKey<VoidBrowserState>());
    // B-012: lets the drag accumulator fire the swipe flash when prev/next triggers.
    final heroFeedbackKey = useMemoized(() => GlobalKey<HeroFeedbackSurfaceState>());

    // Controller: external (test-owned) or self-created + disposed.
    final ownsLibraryController = libraryController == null;
    final libCtrl = useMemoized(
      () =>
          libraryController ??
          LibraryController(
            libraryBrowser: LibraryBrowser(
              supportedExtensions: AudioPlayerProvider.supportedExtensions,
            ),
            libraryService: LibraryService(),
          ),
      [libraryController],
    );
    useEffect(() {
      return ownsLibraryController ? libCtrl.dispose : null;
    }, [libCtrl]);

    final searchController = useTextEditingController();
    final searchFocusNode = useFocusNode();

    // B-003: immersive ramp drives hero growth + browser/crumb collapse so they
    // sum to the available height every frame (no overflow).
    final immersiveCtrl =
        useAnimationController(duration: const Duration(milliseconds: 240));
    final immersiveT = useMemoized(
        () => CurvedAnimation(parent: immersiveCtrl, curve: Curves.easeOutCubic),
        [immersiveCtrl]);
    // B-033: 280 ms easeOutCubic — snappier than MaterialPageRoute.
    // swipe-up browser slide (0=parked, 1=resting; 1 for non-swipe-up).
    final browserSlideCtrl =
        useAnimationController(duration: const Duration(milliseconds: 280));
    final browserSlideT = useMemoized(
        () =>
            CurvedAnimation(parent: browserSlideCtrl, curve: Curves.easeOutCubic),
        [browserSlideCtrl]);

    final immersive = useState(settingsService.immersiveNotifier.value);
    final transportPosition =
        useState(settingsService.transportPositionNotifier.value);
    final browserPresentation =
        useState(settingsService.browserPresentationNotifier.value);
    final browserExpanded = useState(false);
    final searchMode = useState(false);
    // B-043: true when entering search auto-expanded a collapsed swipe-up browser.
    final searchAutoExpandedBrowser = useState(false);
    final showHint = useState(false);
    final hintFaded = useState(false);

    final swipeUpAccum = useRef<double>(0);
    final lastPersistedPath = useRef<String?>(null);
    final hintFadeTimer = useRef<Timer?>(null);
    final jumpGlyphHideTimer = useRef<Timer?>(null);
    // B-031: the latch is a ref (mutated during build, mirroring the old plain
    // field) so flipping it true never notifies mid-build; the hide-timer bumps
    // [rebuildTick] to force the one rebuild that drops the glyph.
    final jumpGlyphLatched = useRef<bool>(false);
    final rebuildTick = useState(0);

    // Mounted check for async callbacks (replaces State.mounted).
    bool isMounted() => context.mounted;

    // Seed initial controller values once (initState parity).
    final didSeed = useRef<bool>(false);
    if (!didSeed.value) {
      didSeed.value = true;
      if (immersive.value) immersiveCtrl.value = 1.0;
      // swipeUp starts collapsed (t=0); fixed is always at rest (t=1).
      browserSlideCtrl.value =
          browserPresentation.value == BrowserPresentation.swipeUp ? 0.0 : 1.0;
    }

    // --- setBrowserExpanded --------------------------------------------------

    // B-033: single entry point for flipping `browserExpanded`; keeps the slide
    // controller in lockstep with the boolean.
    void setBrowserExpanded(bool next) {
      if (browserExpanded.value == next) return;
      browserExpanded.value = next;
      next ? browserSlideCtrl.forward() : browserSlideCtrl.reverse();
    }

    // --- search --------------------------------------------------------------

    void endSearchSession() {
      if (!isMounted()) return;
      // Fire-and-forget; provider treats no-active-session as a no-op.
      unawaited(context.read<AudioPlayerProvider>().exitSearchSession());
    }

    // B-043: undo a search-driven browser expansion; no-op unless
    // [enterSearchMode] auto-expanded a collapsed swipe-up browser.
    void maybeRestoreBrowserAfterSearch() {
      if (!searchAutoExpandedBrowser.value) return;
      searchAutoExpandedBrowser.value = false;
      if (browserPresentation.value == BrowserPresentation.swipeUp &&
          browserExpanded.value) {
        setBrowserExpanded(false);
      }
    }

    void exitSearchMode() {
      searchController.clear();
      searchFocusNode.unfocus();
      searchMode.value = false;
      maybeRestoreBrowserAfterSearch(); // B-043
      endSearchSession(); // B-014
    }

    void enterSearchMode() {
      // B-043 + keyboard-flicker fix: mounting the autofocus field during the
      // 280 ms slide makes Android cancel/hide the keyboard, so for a collapsed
      // swipe-up browser expand first and mount the field once the slide settles.
      if (browserPresentation.value == BrowserPresentation.swipeUp &&
          !browserExpanded.value) {
        searchAutoExpandedBrowser.value = true;
        setBrowserExpanded(true);
        browserSlideCtrl.forward().whenComplete(() {
          if (isMounted()) searchMode.value = true;
        });
        return;
      }
      searchMode.value = true;
    }

    // --- swipe-up browser ----------------------------------------------------

    // Upward drag on the expanded hero: 30 px past threshold expands the browser.
    void onHeroVerticalDrag(DragUpdateDetails d) {
      if (browserExpanded.value ||
          browserPresentation.value != BrowserPresentation.swipeUp) {
        return;
      }
      swipeUpAccum.value += d.primaryDelta ?? 0;
      if (swipeUpAccum.value < -30) {
        setBrowserExpanded(true);
        swipeUpAccum.value = 0;
      }
    }

    void onHeroVerticalDragEnd(DragEndDetails _) => swipeUpAccum.value = 0;

    // B-032: collapse the swipe-up browser (mirrors onPopInvoked's back branch).
    void collapseSwipeUpBrowser() {
      if (!isMounted()) return;
      if (browserPresentation.value != BrowserPresentation.swipeUp) return;
      if (browserExpanded.value) setBrowserExpanded(false);
    }

    // Android back: collapse the swipe-up browser, then exit search, then walk
    // one folder up. Only when all three are exhausted does the OS leave.
    void onPopInvoked(bool didPop, Object? _) {
      if (didPop) return;
      if (browserExpanded.value &&
          browserPresentation.value == BrowserPresentation.swipeUp) {
        setBrowserExpanded(false);
      } else if (searchMode.value) {
        exitSearchMode();
      } else if (libCtrl.currentPath != null) {
        libCtrl.navigateUp();
      }
    }

    // --- jump-to-now-playing -------------------------------------------------

    // B-031: latch true immediately when [divergent]; false only after the
    // predicate stays false for [_jumpGlyphHideDebounce].
    bool resolveJumpGlyphVisible(bool divergent) {
      if (divergent) {
        jumpGlyphHideTimer.value?.cancel();
        jumpGlyphHideTimer.value = null;
        jumpGlyphLatched.value = true;
        return true;
      }
      if (!jumpGlyphLatched.value) return false;
      // Latch still true — arm one hide timer (don't reset on ordinary rebuilds).
      jumpGlyphHideTimer.value ??= Timer(_jumpGlyphHideDebounce, () {
        jumpGlyphHideTimer.value = null;
        if (isMounted()) {
          jumpGlyphLatched.value = false;
          rebuildTick.value++; // force the one rebuild that drops the glyph
        }
      });
      return true;
    }

    // B-015 / B-031: open the swipe-up browser if dismissed, navigate to
    // [playingPath]'s parent, centre the now-playing row.
    Future<void> jumpToNowPlaying(String playingPath) async {
      final parent = p.dirname(playingPath);
      if (parent.isEmpty) return;
      if (browserPresentation.value == BrowserPresentation.swipeUp &&
          !browserExpanded.value) {
        setBrowserExpanded(true);
        await Future<void>.delayed(_browserOpenSettle);
        if (!isMounted()) return;
      }
      if (libCtrl.currentPath != parent) {
        await libCtrl.loadFolder(parent);
      }
      if (!isMounted()) return;
      await browserKey.currentState?.scrollToTrack(playingPath);
    }

    // --- listeners -----------------------------------------------------------

    void onImmersiveChanged() {
      final next = settingsService.immersiveNotifier.value;
      if (immersive.value == next) return;
      immersive.value = next;
      next ? immersiveCtrl.forward() : immersiveCtrl.reverse();
    }

    void onTransportPositionChanged() {
      final next = settingsService.transportPositionNotifier.value;
      if (transportPosition.value == next) return;
      transportPosition.value = next;
    }

    void onBrowserPresentationChanged() {
      final next = settingsService.browserPresentationNotifier.value;
      if (browserPresentation.value == next) return;
      browserPresentation.value = next;
      browserExpanded.value = false;
      // B-033: swipeUp starts collapsed (t=0); fixed rests (t=1).
      browserSlideCtrl.value = next == BrowserPresentation.swipeUp ? 0.0 : 1.0;
    }

    void onLibraryChanged() {
      if (!isMounted()) return;
      // PopScope.canPop refresh + children Provider updates come for free via
      // useListenable(libCtrl) below; here we only persist navigation so the
      // next launch returns to the same folder.
      final path = libCtrl.currentPath;
      if (path != lastPersistedPath.value) {
        lastPersistedPath.value = path;
        settingsService.saveLastLibraryPath(path);
      }
    }

    void onSearchFocusChanged() {
      // B-013: collapse on focus-out regardless of query (tap-away ends session).
      if (!searchFocusNode.hasFocus && searchMode.value) {
        searchMode.value = false;
        searchController.clear();
        maybeRestoreBrowserAfterSearch(); // B-043
        endSearchSession(); // B-014
      }
    }

    // Wire (listenable, callback) pairs; rebuild-only notifiers are subscribed
    // via useListenable so a fire rebuilds the HookWidget.
    useEffect(() {
      searchFocusNode.addListener(onSearchFocusChanged);
      settingsService.immersiveNotifier.addListener(onImmersiveChanged);
      settingsService.transportPositionNotifier
          .addListener(onTransportPositionChanged);
      settingsService.browserPresentationNotifier
          .addListener(onBrowserPresentationChanged);
      libCtrl.addListener(onLibraryChanged);
      return () {
        searchFocusNode.removeListener(onSearchFocusChanged);
        settingsService.immersiveNotifier.removeListener(onImmersiveChanged);
        settingsService.transportPositionNotifier
            .removeListener(onTransportPositionChanged);
        settingsService.browserPresentationNotifier
            .removeListener(onBrowserPresentationChanged);
        libCtrl.removeListener(onLibraryChanged);
      };
    }, [libCtrl, searchFocusNode]);

    // screenConfigNotifier + libraryController drive rebuilds (settings cycle-row
    // changes + PopScope.canPop refresh). useListenable rebuilds on every fire.
    useListenable(settingsService.screenConfigNotifier);
    useListenable(libCtrl);

    // DebugHooks register + clear (B-driving seams).
    useEffect(() {
      DebugHooks.libraryController = libCtrl;
      DebugHooks.immersiveLookup = () => immersive.value;
      return () {
        DebugHooks.immersiveLookup = null;
        DebugHooks.libraryController = null;
      };
    }, [libCtrl]);

    // Controller's first init + one-shot restore of the last browsed path.
    useEffect(() {
      if (!ownsLibraryController) return null;
      Future<void> bootstrap() async {
        await libCtrl.init();
        if (!isMounted()) return;
        final saved = await settingsService.loadLastLibraryPath();
        if (!isMounted()) return;
        if (saved == null || saved.isEmpty) return;
        if (libCtrl.currentPath == saved) return;
        // Record the target so the listener doesn't re-persist what we loaded.
        lastPersistedPath.value = saved;
        try {
          await libCtrl.loadFolder(saved);
        } catch (_) {
          // Folder gone — clear stale pointer, fall back to loadRoot()'s landing.
          await settingsService.saveLastLibraryPath(null);
        }
      }

      bootstrap();
      return null;
    }, [libCtrl]);

    // B-005: launch hint shown on every mount, fades after 3 s.
    useEffect(() {
      showHint.value = true;
      hintFaded.value = false;
      hintFadeTimer.value?.cancel();
      hintFadeTimer.value = Timer(const Duration(seconds: 3), () {
        if (isMounted()) hintFaded.value = true;
      });
      return () => hintFadeTimer.value?.cancel();
    }, const []);

    // Cancel the jump-glyph debounce timer on unmount.
    useEffect(() => () => jumpGlyphHideTimer.value?.cancel(), const []);

    // --- theming helpers -----------------------------------------------------

    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final typography = theme.extension<AppTypography>()!;
    final geometry = theme.extension<AppGeometry>()!;

    // Mono text style helper — shared by crumb/glyph/hint text.
    TextStyle mono(
      Color color,
      double size, {
      double? letterSpacing,
      double? height,
    }) =>
        TextStyle(
          color: color,
          fontFamily: typography.monoFamily,
          fontSize: size,
          letterSpacing: letterSpacing,
          height: height,
        );

    // Tap target wrapping a mono [glyph] in [Semantics] + [PressFeedback]; sized
    // [box]×[box] (Material min). Used by crumb-jump, search-close, settings.
    Widget glyphButton({
      required String semanticsLabel,
      required Key? buttonKey,
      required VoidCallback onTap,
      required double box,
      required String glyph,
      required TextStyle style,
    }) =>
        Semantics(
          label: semanticsLabel,
          button: true,
          child: PressFeedback(
            key: buttonKey,
            onTap: onTap,
            child: SizedBox(
              width: box,
              height: box,
              child: Center(child: Text(glyph, style: style)),
            ),
          ),
        );

    // Active config: constructor value, else screenConfigNotifier.
    ScreenConfig resolvedScreenConfig() =>
        config ?? settingsService.screenConfigNotifier.value;

    // Map the active screen type onto its hero widget.
    Widget buildHeroFor(ScreenConfig cfg) {
      switch (cfg.type) {
        case ScreenType.void_:
          return VoidHero(config: cfg as VoidScreenConfig);
        case ScreenType.spectrum:
          return SpectrumHero(
            config: cfg as SpectrumScreenConfig,
            settings: settings ?? settingsService.settingsNotifier.value,
          );
        case ScreenType.polo:
          return PoloHero(
            config: cfg as PoloScreenConfig,
            debugLayout: settingsService.debugLayoutNotifier.value,
          );
        case ScreenType.dot:
          return DotHero(config: cfg as DotScreenConfig);
      }
    }

    // --- builders ------------------------------------------------------------

    // Wraps the hero in a [HeroFeedbackSurface]; vertical drag is wired only when
    // the swipe-up browser is collapsed. positionMs/durationMs are getters so
    // position ticks don't rebuild.
    Widget buildHeroGestureSurface({required Widget child}) {
      final player = context.read<AudioPlayerProvider>();
      final acceptVertical =
          browserPresentation.value == BrowserPresentation.swipeUp &&
              !browserExpanded.value;
      return HeroFeedbackSurface(
        key: heroFeedbackKey,
        onPlayPause: () => player.playPause(),
        onPrevious: () => player.previous(),
        onNext: () => player.next(),
        onSeek: (d) => player.seek(d),
        positionMs: () => player.songInfo?.position ?? 0,
        durationMs: () => player.songInfo?.duration ?? 0,
        onVerticalDragUpdate: acceptVertical ? onHeroVerticalDrag : null,
        onVerticalDragEnd: acceptVertical ? onHeroVerticalDragEnd : null,
        child: child,
      );
    }

    // B-015: "jump to what's playing" tap target — `⊙` in fgPrimary at rowSize
    // (B-033 contrast bump), 44×44 hit target (B-013).
    Widget buildJumpGlyph(String playingPath) => glyphButton(
          semanticsLabel: 'jump to now-playing folder',
          buttonKey: const ValueKey('void-crumb-jump-to-playing'),
          onTap: () => jumpToNowPlaying(playingPath),
          box: 44,
          glyph: '⊙', // ⊙ — CIRCLED DOT OPERATOR
          style: mono(palette.fgPrimary, typography.rowSize, height: 1),
        );

    Widget buildSearchCrumb() {
      // B-013: input at row-size; × keeps tertiary tone at crumbSize with a 44 px
      // hit target; row accepts a downward swipe as dismissal.
      final textStyle = mono(palette.fgPrimary, typography.rowSize);
      return GestureDetector(
        key: const ValueKey('void-search-crumb-region'),
        behavior: HitTestBehavior.opaque,
        // Downward fling dismisses (mirrors × tap); TextField keeps scroll/long-press.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 200) exitSearchMode();
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('? ', style: textStyle.copyWith(color: palette.fgSecondary)),
            Expanded(
              child: TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                // autofocus is the single keyboard trigger; requestFocus raced
                // the expand rebuild and flashed the keyboard.
                autofocus: true,
                cursorColor: palette.fgPrimary,
                cursorWidth: 1,
                style: textStyle,
                decoration: const InputDecoration.collapsed(hintText: ''),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => exitSearchMode(),
              ),
            ),
            glyphButton(
              semanticsLabel: 'close search',
              buttonKey: const ValueKey('void-search-close'),
              onTap: exitSearchMode,
              box: 44,
              glyph: '×',
              style: mono(palette.fgTertiary, typography.crumbSize),
            ),
          ],
        ),
      );
    }

    Widget buildCrumb() {
      // Path readout that morphs into "? <query>" on long-press; a hidden
      // TextField captures keystrokes in search mode, collapsing on tap-away.
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
                color: palette.divider, width: geometry.dividerThickness),
          ),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: searchMode.value ? null : enterSearchMode,
          child: Builder(
            builder: (context) {
              if (searchMode.value) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: buildSearchCrumb(),
                );
              }
              LibraryController? controller;
              try {
                controller = Provider.of<LibraryController>(context);
              } catch (_) {/* not provided */}
              final path = controller?.currentPath;
              // B-015: show the jump glyph when the playing track lives outside
              // the browsed folder; B-031 debounces the hide.
              final player = context.watch<AudioPlayerProvider>();
              final playingPath = player.songInfo?.track.path;
              final divergent = playingPath != null &&
                  playingPath.isNotEmpty &&
                  p.dirname(playingPath) != (path ?? '');
              final showJumpGlyph = resolveJumpGlyphVisible(divergent);
              // 12-px vertical padding preserves the crumb baseline; the 44×44
              // glyph hit target sits outside it (Material min, B-013).
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 0, 12),
                      child: MidEllipsis(
                        text: path == null || path.isEmpty ? '~' : path,
                        style: mono(
                            palette.fgSecondary, typography.crumbSize),
                      ),
                    ),
                  ),
                  if (showJumpGlyph && playingPath != null)
                    buildJumpGlyph(playingPath)
                  else
                    const SizedBox(width: 20),
                ],
              );
            },
          ),
        ),
      );
    }

    Widget buildProgressHairline() {
      final si = context.watch<AudioPlayerProvider>().songInfo;
      final position = si?.position ?? 0;
      final duration = si?.duration ?? 0;
      final fraction =
          duration <= 0 ? 0.0 : (position / duration).clamp(0.0, 1.0);
      return SizedBox(
        height: 1,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: Container(color: palette.progress),
          ),
        ),
      );
    }

    Widget buildSettingsButton() {
      // B-004: 48 dp tap target with a perceptible glyph.
      return Positioned(
        top: 4,
        right: 4,
        child: glyphButton(
          semanticsLabel: 'settings',
          buttonKey: const ValueKey('void-settings-button'),
          onTap: () => VoidSettingsSheet.push(context),
          box: 48,
          glyph: '⋮', // U+22EE VERTICAL ELLIPSIS — readable in mono
          style: mono(palette.fgPrimary.withAlpha(180), typography.rowSize + 4,
              height: 1),
        ),
      );
    }

    Widget buildSwipeUpHint() {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: onHeroVerticalDrag,
        onVerticalDragEnd: onHeroVerticalDragEnd,
        child: PressFeedback(
          onTap: () => setBrowserExpanded(true),
          child: Container(
            alignment: Alignment.center,
            child: Text(
              '↑ swipe to browse',
              style: mono(palette.fgTertiary, typography.hintSize,
                  letterSpacing: 0.2),
            ),
          ),
        ),
      );
    }

    Widget buildHint() {
      if (!showHint.value) return const SizedBox.shrink();
      return Positioned(
        top: 12,
        right: 14,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: hintFaded.value ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 800),
            child: Text(
              'tap · long-press · swipe',
              style: mono(palette.fgQuaternary, typography.hintSize,
                  letterSpacing: 0.18),
            ),
          ),
        ),
      );
    }

    // Frame's animated layout off the immersive ramp `t` and swipe-up slide `s`.
    // Everything hangs off the bottom edge so hero growth never overflows a fixed
    // slot mid-transition (B-003); hero lerps collapsed (s=0) ↔ expanded (s=1).
    _Layout layout(double availableH, double heroHeight, double bottomInset) {
      final t = immersiveT.value;
      final swipeUp = browserPresentation.value == BrowserPresentation.swipeUp;
      final s = swipeUp ? browserSlideT.value : 1.0;
      // reservedBottom keeps crumb + hairline above the gesture-nav bar (B-002);
      // shrinks to 0 in immersive so the hero meets the edge.
      final reservedBottom = bottomInset * (1 - t);
      // B-018: only hosted heroes (not bespoke Polo) get a chrome transport row.
      final hostsTransport = resolvedScreenConfig().hostsChromeTransport;
      final isTransportTop =
          hostsTransport && transportPosition.value == TransportPosition.top;
      final isTransportBottom =
          hostsTransport && transportPosition.value == TransportPosition.bottom;
      final browserBottom = reservedBottom +
          _crumbHeight +
          (isTransportBottom ? _transportHeight : 0.0);
      final heroHCollapsed = availableH -
          browserBottom -
          _swipeHintZoneHeight -
          (isTransportTop ? _transportHeight : 0.0);
      final baseHeroH = heroHCollapsed + (heroHeight - heroHCollapsed) * s;
      final heroH = baseHeroH + (availableH - baseHeroH) * t;
      final restingBrowserTop =
          heroHeight + (isTransportTop ? _transportHeight : 0.0);
      final restingBrowserHeight = (availableH - restingBrowserTop - browserBottom)
          .clamp(0.0, availableH);
      return _Layout(
        s: s,
        reservedBottom: reservedBottom,
        showChildren: t < 0.999,
        isTransportTop: isTransportTop,
        isTransportBottom: isTransportBottom,
        browserBottom: browserBottom,
        heroH: heroH,
        browserTop: availableH + (restingBrowserTop - availableH) * s,
        browserBottomAnimated:
            -restingBrowserHeight + (browserBottom + restingBrowserHeight) * s,
        swipeUp: swipeUp,
        // Hint fades as the slide progresses so it can't collide with browser chrome.
        hintOpacity: swipeUp ? (1.0 - s).clamp(0.0, 1.0) : 0.0,
      );
    }

    Widget buildStack(_Layout m) {
      final hasTransport = m.isTransportTop || m.isTransportBottom;
      return Stack(
        children: [
          // Hero — anchored top, animated height; gesture surface owns taps + seek.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: m.heroH,
            child: buildHeroGestureSurface(
              child: buildHeroFor(resolvedScreenConfig()),
            ),
          ),
          // Browser — always in the tree (B-033) so the slide has a target;
          // parked offscreen + IgnorePointer at s≈0 when collapsed.
          if (m.showChildren)
            Positioned(
              top: m.browserTop,
              left: 0,
              right: 0,
              bottom: m.browserBottomAnimated,
              child: IgnorePointer(
                ignoring: m.s < 0.01,
                child: ClipRect(
                  clipBehavior: Clip.hardEdge,
                  child: VoidBrowser(
                    key: browserKey,
                    controller: libCtrl,
                    searchController: searchController,
                    // B-032: drag-down close only in swipe-up; fixed stays
                    // anchored (no handle/gesture).
                    isDismissable: m.swipeUp && browserExpanded.value,
                    onDragDownClose: collapseSwipeUpBrowser,
                  ),
                ),
              ),
            ),
          // Swipe-up hint band — tap / upward drag expands the browser; fades as
          // the browser slides up (B-033).
          if (m.showChildren && m.swipeUp && m.hintOpacity > 0.001)
            Positioned(
              left: 0,
              right: 0,
              height: _swipeHintZoneHeight,
              bottom: m.browserBottom,
              child: IgnorePointer(
                ignoring: browserExpanded.value,
                child: Opacity(
                  opacity: m.hintOpacity,
                  child: buildSwipeUpHint(),
                ),
              ),
            ),
          // Transport row — top (below hero) or bottom (above crumb); hidden in
          // immersive or when position == off.
          if (m.showChildren && hasTransport)
            Positioned(
              left: 0,
              right: 0,
              top: m.isTransportTop ? m.heroH : null,
              bottom: m.isTransportBottom
                  ? m.reservedBottom + _crumbHeight
                  : null,
              height: _transportHeight,
              child: const TransportRow(),
            ),
          // Crumb — anchored above the gesture-nav bar.
          if (m.showChildren)
            Positioned(
              left: 0,
              right: 0,
              bottom: m.reservedBottom,
              height: _crumbHeight,
              child: buildCrumb(),
            ),
          // Settings button — top-right, hidden in immersive.
          if (m.showChildren) buildSettingsButton(),
          // Cold-launch gesture hint — above everything.
          buildHint(),
          // Progress hairline — bottom, above gesture-nav bar (B-002).
          Positioned(
            left: 0,
            right: 0,
            bottom: m.reservedBottom,
            child: buildProgressHairline(),
          ),
        ],
      );
    }

    // --- build ---------------------------------------------------------------

    final mq = MediaQuery.of(context);
    final heroHeight = mq.size.height * geometry.heroFraction;
    final bottomInset = mq.viewPadding.bottom;

    return PopScope(
      canPop: libCtrl.currentPath == null &&
          !searchMode.value &&
          !(browserExpanded.value &&
              browserPresentation.value == BrowserPresentation.swipeUp),
      onPopInvokedWithResult: onPopInvoked,
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          bottom: false,
          child: ChangeNotifierProvider<LibraryController>.value(
            value: libCtrl,
            child: LayoutBuilder(
              builder: (context, c) {
                final availableH = c.maxHeight;
                // B-033: one AnimatedBuilder on both ramps so shared metrics never drift.
                return AnimatedBuilder(
                  animation: Listenable.merge([immersiveT, browserSlideT]),
                  builder: (context, _) => buildStack(
                    layout(availableH, heroHeight, bottomInset),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-frame layout metrics computed by [VoidScreen]'s layout helper.
class _Layout {
  const _Layout({
    required this.s,
    required this.reservedBottom,
    required this.showChildren,
    required this.isTransportTop,
    required this.isTransportBottom,
    required this.browserBottom,
    required this.heroH,
    required this.browserTop,
    required this.browserBottomAnimated,
    required this.swipeUp,
    required this.hintOpacity,
  });

  final double s;
  final double reservedBottom;
  final bool showChildren;
  final bool isTransportTop;
  final bool isTransportBottom;
  final double browserBottom;
  final double heroH;
  final double browserTop;
  final double browserBottomAnimated;
  final bool swipeUp;
  final double hintOpacity;
}
