import 'dart:async';

import 'package:flutter/material.dart';
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

/// Home shell for all four visualisations: hero, embedded [VoidBrowser],
/// transport row, crumb (path / search), progress hairline. Hero tap-zones
/// (prev/play-pause/next) + drag-to-seek; immersive mode hides chrome.
class VoidScreen extends StatefulWidget {
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
  State<VoidScreen> createState() => _VoidScreenState();
}

class _VoidScreenState extends State<VoidScreen> with TickerProviderStateMixin {
  // Fixed slot heights.
  static const double _crumbHeight = 56.0;
  static const double _transportHeight = TransportRow.transportHeight;
  static const double _swipeHintZoneHeight = 56.0;

  // B-031: hide-only debounce for the crumb's ⊙ jump glyph — filters one-frame
  // races where dirname(songInfo.path) briefly == currentPath on track changes.
  static const Duration _jumpGlyphHideDebounce = Duration(milliseconds: 200);
  // Settle window after opening the browser so its first frame lays out before
  // we navigate + scroll; ~250 ms reads as one gesture.
  static const Duration _browserOpenSettle = Duration(milliseconds: 250);

  final SettingsService _settings = SettingsService();
  late final LibraryController _libraryController;
  late final bool _ownsLibraryController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // B-003: immersive ramp drives hero growth + browser/crumb collapse so they
  // sum to the available height every frame (no overflow).
  late final AnimationController _immersiveCtrl;
  late final Animation<double> _immersiveT;
  // B-033: swipe-up browser slide (0=parked, 1=resting; 1 for non-swipe-up).
  // Non-final for hot reload.
  late AnimationController _browserSlideCtrl;
  late Animation<double> _browserSlideT;

  bool _immersive = false;
  TransportPosition _transportPosition = TransportPosition.bottom;
  BrowserPresentation _browserPresentation = BrowserPresentation.fixed;
  bool _browserExpanded = false;
  double _swipeUpAccum = 0;
  String? _lastPersistedPath;
  bool _showHint = false;
  bool _hintFaded = false;
  bool _searchMode = false;
  // B-043: true when entering search auto-expanded a collapsed swipe-up browser.
  bool _searchAutoExpandedBrowser = false;
  bool _jumpGlyphLatched = false;
  Timer? _hintFadeTimer;
  Timer? _jumpGlyphHideTimer;

  // B-012: lets the drag accumulator fire the swipe flash when prev/next triggers.
  final GlobalKey<HeroFeedbackSurfaceState> _heroFeedbackKey = GlobalKey();
  // B-015: lets the crumb's jump tap drive scrollToTrack after loadFolder.
  final GlobalKey<VoidBrowserState> _browserKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ownsLibraryController = widget.libraryController == null;
    _libraryController = widget.libraryController ??
        LibraryController(
          libraryBrowser: LibraryBrowser(
            supportedExtensions: AudioPlayerProvider.supportedExtensions,
          ),
          libraryService: LibraryService(),
        );
    if (_ownsLibraryController) _bootstrapLibrary();

    final (imCtrl, imT) = _curved(const Duration(milliseconds: 240));
    _immersiveCtrl = imCtrl;
    _immersiveT = imT;
    // B-033: 280 ms easeOutCubic — snappier than MaterialPageRoute.
    final (bsCtrl, bsT) = _curved(const Duration(milliseconds: 280));
    _browserSlideCtrl = bsCtrl;
    _browserSlideT = bsT;

    _immersive = _settings.immersiveNotifier.value;
    _transportPosition = _settings.transportPositionNotifier.value;
    _browserPresentation = _settings.browserPresentationNotifier.value;
    if (_immersive) _immersiveCtrl.value = 1.0;
    // swipeUp starts collapsed (t=0); fixed is always at rest (t=1).
    _browserSlideCtrl.value =
        _browserPresentation == BrowserPresentation.swipeUp ? 0.0 : 1.0;

    for (final (listenable, cb) in _listenerBindings()) {
      listenable.addListener(cb);
    }
    _maybeShowLaunchHint();

    DebugHooks.libraryController = _libraryController;
    DebugHooks.immersiveLookup = () => _immersive;
  }

  /// (listenable, callback) pairs wired in [initState], unwired in [dispose].
  List<(Listenable, VoidCallback)> _listenerBindings() => [
        (_searchFocusNode, _onSearchFocusChanged),
        (_settings.immersiveNotifier, _onImmersiveChanged),
        (_settings.transportPositionNotifier, _onTransportPositionChanged),
        (_settings.browserPresentationNotifier, _onBrowserPresentationChanged),
        (_settings.screenConfigNotifier, _onScreenConfigChanged),
        (_libraryController, _onLibraryChanged),
      ];

  /// AnimationController ([duration]) + easeOutCubic CurvedAnimation, disposed
  /// in [dispose]. Caller keeps both for forward/reverse + value reads.
  (AnimationController, Animation<double>) _curved(Duration duration) {
    final c = AnimationController(vsync: this, duration: duration);
    return (c, CurvedAnimation(parent: c, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _hintFadeTimer?.cancel();
    _jumpGlyphHideTimer?.cancel();
    for (final (listenable, cb) in _listenerBindings()) {
      listenable.removeListener(cb);
    }
    _searchFocusNode.dispose();
    _searchController.dispose();
    _immersiveCtrl.dispose();
    _browserSlideCtrl.dispose();
    DebugHooks.immersiveLookup = null;
    DebugHooks.libraryController = null;
    if (_ownsLibraryController) _libraryController.dispose();
    super.dispose();
  }

  // --- listeners -----------------------------------------------------------

  void _onImmersiveChanged() {
    final next = _settings.immersiveNotifier.value;
    if (_immersive == next) return;
    setState(() => _immersive = next);
    next ? _immersiveCtrl.forward() : _immersiveCtrl.reverse();
  }

  void _onTransportPositionChanged() {
    final next = _settings.transportPositionNotifier.value;
    if (_transportPosition == next) return;
    setState(() => _transportPosition = next);
  }

  void _onBrowserPresentationChanged() {
    final next = _settings.browserPresentationNotifier.value;
    if (_browserPresentation == next) return;
    setState(() {
      _browserPresentation = next;
      _browserExpanded = false;
    });
    // B-033: swipeUp starts collapsed (t=0); fixed rests (t=1).
    _browserSlideCtrl.value = next == BrowserPresentation.swipeUp ? 0.0 : 1.0;
  }

  void _onLibraryChanged() {
    if (!mounted) return;
    // Refresh PopScope.canPop; children get their own Provider updates.
    setState(() {});
    // Persist navigation so the next launch returns to the same folder.
    final path = _libraryController.currentPath;
    if (path != _lastPersistedPath) {
      _lastPersistedPath = path;
      _settings.saveLastLibraryPath(path);
    }
  }

  void _onScreenConfigChanged() {
    // setState picks up settings cycle-row changes without a parent rebuild.
    if (mounted) setState(() {});
  }

  /// Controller's first init + one-shot restore of the last browsed path.
  Future<void> _bootstrapLibrary() async {
    await _libraryController.init();
    if (!mounted) return;
    final saved = await _settings.loadLastLibraryPath();
    if (!mounted) return;
    if (saved == null || saved.isEmpty) return;
    if (_libraryController.currentPath == saved) return;
    // Record the target so the listener doesn't re-persist what we loaded.
    _lastPersistedPath = saved;
    try {
      await _libraryController.loadFolder(saved);
    } catch (_) {
      // Folder gone — clear stale pointer, fall back to loadRoot()'s landing.
      await _settings.saveLastLibraryPath(null);
    }
  }

  // --- search --------------------------------------------------------------

  void _onSearchFocusChanged() {
    // B-013: collapse on focus-out regardless of query (tap-away ends session).
    if (!_searchFocusNode.hasFocus && _searchMode) {
      setState(() => _searchMode = false);
      _searchController.clear();
      _maybeRestoreBrowserAfterSearch(); // B-043
      _endSearchSession(); // B-014
    }
  }

  void _enterSearchMode() {
    // B-043 + keyboard-flicker fix: mounting the autofocus field during the
    // 280 ms slide makes Android cancel/hide the keyboard, so for a collapsed
    // swipe-up browser expand first and mount the field once the slide settles.
    if (_browserPresentation == BrowserPresentation.swipeUp &&
        !_browserExpanded) {
      _searchAutoExpandedBrowser = true;
      _setBrowserExpanded(true);
      _browserSlideCtrl.forward().whenComplete(() {
        if (mounted) setState(() => _searchMode = true);
      });
      return;
    }
    setState(() => _searchMode = true);
  }

  void _exitSearchMode() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() => _searchMode = false);
    _maybeRestoreBrowserAfterSearch(); // B-043
    _endSearchSession(); // B-014
  }

  /// B-043: undo a search-driven browser expansion; no-op unless
  /// [_enterSearchMode] auto-expanded a collapsed swipe-up browser.
  void _maybeRestoreBrowserAfterSearch() {
    if (!_searchAutoExpandedBrowser) return;
    _searchAutoExpandedBrowser = false;
    if (_browserPresentation == BrowserPresentation.swipeUp &&
        _browserExpanded) {
      _setBrowserExpanded(false);
    }
  }

  void _endSearchSession() {
    if (!mounted) return;
    // Fire-and-forget; provider treats no-active-session as a no-op.
    unawaited(context.read<AudioPlayerProvider>().exitSearchSession());
  }

  // --- hint ----------------------------------------------------------------

  void _maybeShowLaunchHint() {
    // B-005: shown on every mount, fades after 3 s.
    if (!mounted) return;
    setState(() {
      _showHint = true;
      _hintFaded = false;
    });
    _hintFadeTimer?.cancel();
    _hintFadeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _hintFaded = true);
    });
  }

  // --- swipe-up browser ----------------------------------------------------

  /// Upward drag on the expanded hero: 30 px past threshold expands the browser.
  void _onHeroVerticalDrag(DragUpdateDetails d) {
    if (_browserExpanded ||
        _browserPresentation != BrowserPresentation.swipeUp) {
      return;
    }
    _swipeUpAccum += d.primaryDelta ?? 0;
    if (_swipeUpAccum < -30) {
      _setBrowserExpanded(true);
      _swipeUpAccum = 0;
    }
  }

  void _onHeroVerticalDragEnd(DragEndDetails _) => _swipeUpAccum = 0;

  /// B-032: collapse the swipe-up browser (mirrors [_onPopInvoked]'s back branch).
  void _collapseSwipeUpBrowser() {
    if (!mounted) return;
    if (_browserPresentation != BrowserPresentation.swipeUp) return;
    if (_browserExpanded) _setBrowserExpanded(false);
  }

  /// B-033: single entry point for flipping `_browserExpanded`; keeps the slide
  /// controller in lockstep with the boolean.
  void _setBrowserExpanded(bool next) {
    if (_browserExpanded == next) return;
    setState(() => _browserExpanded = next);
    next ? _browserSlideCtrl.forward() : _browserSlideCtrl.reverse();
  }

  /// Android back: collapse the swipe-up browser, then exit search, then walk
  /// one folder up. Only when all three are exhausted does the OS leave.
  void _onPopInvoked(bool didPop, Object? _) {
    if (didPop) return;
    if (_browserExpanded &&
        _browserPresentation == BrowserPresentation.swipeUp) {
      _setBrowserExpanded(false);
    } else if (_searchMode) {
      _exitSearchMode();
    } else if (_libraryController.currentPath != null) {
      _libraryController.navigateUp();
    }
  }

  // --- jump-to-now-playing -------------------------------------------------

  /// B-031: latch true immediately when [divergent]; false only after the
  /// predicate stays false for [_jumpGlyphHideDebounce].
  bool _resolveJumpGlyphVisible(bool divergent) {
    if (divergent) {
      _jumpGlyphHideTimer?.cancel();
      _jumpGlyphHideTimer = null;
      _jumpGlyphLatched = true;
      return true;
    }
    if (!_jumpGlyphLatched) return false;
    // Latch still true — arm one hide timer (don't reset on ordinary rebuilds).
    _jumpGlyphHideTimer ??= Timer(_jumpGlyphHideDebounce, () {
      _jumpGlyphHideTimer = null;
      if (mounted) setState(() => _jumpGlyphLatched = false);
    });
    return true;
  }

  /// B-015 / B-031: open the swipe-up browser if dismissed, navigate to
  /// [playingPath]'s parent, centre the now-playing row.
  Future<void> _jumpToNowPlaying(String playingPath) async {
    final parent = p.dirname(playingPath);
    if (parent.isEmpty) return;
    if (_browserPresentation == BrowserPresentation.swipeUp &&
        !_browserExpanded) {
      _setBrowserExpanded(true);
      await Future<void>.delayed(_browserOpenSettle);
      if (!mounted) return;
    }
    if (_libraryController.currentPath != parent) {
      await _libraryController.loadFolder(parent);
    }
    if (!mounted) return;
    await _browserKey.currentState?.scrollToTrack(playingPath);
  }

  // --- theming helpers -----------------------------------------------------

  /// The three Void theme extensions, fetched in one go.
  ({AppPalette palette, AppTypography typography, AppGeometry geometry})
      _theme() {
    final t = Theme.of(context);
    return (
      palette: t.extension<AppPalette>()!,
      typography: t.extension<AppTypography>()!,
      geometry: t.extension<AppGeometry>()!,
    );
  }

  /// Mono text style helper — shared by crumb/glyph/hint text.
  TextStyle _mono(
    AppTypography typography,
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

  /// Tap target wrapping a mono [glyph] in [Semantics] + [PressFeedback]; sized
  /// [box]×[box] (Material min). Used by crumb-jump, search-close, settings.
  Widget _glyphButton({
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

  /// Active config: constructor value, else [SettingsService.screenConfigNotifier].
  ScreenConfig _resolvedScreenConfig() =>
      widget.config ?? _settings.screenConfigNotifier.value;

  /// Map the active screen type onto its hero widget.
  Widget _buildHeroFor(ScreenConfig config) {
    switch (config.type) {
      case ScreenType.void_:
        return VoidHero(config: config as VoidScreenConfig);
      case ScreenType.spectrum:
        return SpectrumHero(
          config: config as SpectrumScreenConfig,
          settings: widget.settings ?? _settings.settingsNotifier.value,
        );
      case ScreenType.polo:
        return PoloHero(
          config: config as PoloScreenConfig,
          debugLayout: _settings.debugLayoutNotifier.value,
        );
      case ScreenType.dot:
        return DotHero(config: config as DotScreenConfig);
    }
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final (:palette, :typography, :geometry) = _theme();
    final mq = MediaQuery.of(context);
    final heroHeight = mq.size.height * geometry.heroFraction;
    final bottomInset = mq.viewPadding.bottom;

    return PopScope(
      canPop: _libraryController.currentPath == null &&
          !_searchMode &&
          !(_browserExpanded &&
              _browserPresentation == BrowserPresentation.swipeUp),
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          bottom: false,
          child: ChangeNotifierProvider<LibraryController>.value(
            value: _libraryController,
            child: LayoutBuilder(
              builder: (context, c) {
                final availableH = c.maxHeight;
                // B-033: one AnimatedBuilder on both ramps so shared metrics never drift.
                return AnimatedBuilder(
                  animation: Listenable.merge([_immersiveT, _browserSlideT]),
                  builder: (context, _) => _buildStack(
                    _layout(availableH, heroHeight, bottomInset),
                    palette,
                    typography,
                    geometry,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStack(
    _Layout m,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    final hasTransport = m.isTransportTop || m.isTransportBottom;
    return Stack(
      children: [
        // Hero — anchored top, animated height; gesture surface owns taps + seek.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: m.heroH,
          child: _buildHeroGestureSurface(
            child: _buildHeroFor(_resolvedScreenConfig()),
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
                  key: _browserKey,
                  controller: _libraryController,
                  searchController: _searchController,
                  // B-032: drag-down close only in swipe-up; fixed stays
                  // anchored (no handle/gesture).
                  isDismissable: m.swipeUp && _browserExpanded,
                  onDragDownClose: _collapseSwipeUpBrowser,
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
              ignoring: _browserExpanded,
              child: Opacity(
                opacity: m.hintOpacity,
                child: _buildSwipeUpHint(palette, typography),
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
            child: _buildCrumb(palette, typography, geometry),
          ),
        // Settings button — top-right, hidden in immersive.
        if (m.showChildren) _buildSettingsButton(palette, typography),
        // Cold-launch gesture hint — above everything.
        _buildHint(palette, typography),
        // Progress hairline — bottom, above gesture-nav bar (B-002).
        Positioned(
          left: 0,
          right: 0,
          bottom: m.reservedBottom,
          child: _buildProgressHairline(palette),
        ),
      ],
    );
  }

  /// Frame's animated layout off the immersive ramp `t` and swipe-up slide `s`.
  /// Everything hangs off the bottom edge so hero growth never overflows a fixed
  /// slot mid-transition (B-003); hero lerps collapsed (s=0) ↔ expanded (s=1).
  _Layout _layout(double availableH, double heroHeight, double bottomInset) {
    final t = _immersiveT.value;
    final swipeUp = _browserPresentation == BrowserPresentation.swipeUp;
    final s = swipeUp ? _browserSlideT.value : 1.0;
    // reservedBottom keeps crumb + hairline above the gesture-nav bar (B-002);
    // shrinks to 0 in immersive so the hero meets the edge.
    final reservedBottom = bottomInset * (1 - t);
    // B-018: only hosted heroes (not bespoke Polo) get a chrome transport row.
    final hostsTransport = _resolvedScreenConfig().hostsChromeTransport;
    final isTransportTop =
        hostsTransport && _transportPosition == TransportPosition.top;
    final isTransportBottom =
        hostsTransport && _transportPosition == TransportPosition.bottom;
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
    final restingBrowserHeight =
        (availableH - restingBrowserTop - browserBottom).clamp(0.0, availableH);
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

  /// Wraps the hero in a [HeroFeedbackSurface]; vertical drag is wired only when
  /// the swipe-up browser is collapsed. positionMs/durationMs are getters so
  /// position ticks don't rebuild.
  Widget _buildHeroGestureSurface({required Widget child}) {
    final player = context.read<AudioPlayerProvider>();
    final acceptVertical =
        _browserPresentation == BrowserPresentation.swipeUp &&
            !_browserExpanded;
    return HeroFeedbackSurface(
      key: _heroFeedbackKey,
      onPlayPause: () => player.playPause(),
      onPrevious: () => player.previous(),
      onNext: () => player.next(),
      onSeek: (d) => player.seek(d),
      positionMs: () => player.songInfo?.position ?? 0,
      durationMs: () => player.songInfo?.duration ?? 0,
      onVerticalDragUpdate: acceptVertical ? _onHeroVerticalDrag : null,
      onVerticalDragEnd: acceptVertical ? _onHeroVerticalDragEnd : null,
      child: child,
    );
  }

  Widget _buildCrumb(
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
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
        onLongPress: _searchMode ? null : _enterSearchMode,
        child: Builder(
          builder: (context) {
            if (_searchMode) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: _buildSearchCrumb(palette, typography),
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
            final showJumpGlyph = _resolveJumpGlyphVisible(divergent);
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
                      style: _mono(
                          typography, palette.fgSecondary, typography.crumbSize),
                    ),
                  ),
                ),
                if (showJumpGlyph && playingPath != null)
                  _buildJumpGlyph(palette, typography, playingPath)
                else
                  const SizedBox(width: 20),
              ],
            );
          },
        ),
      ),
    );
  }

  /// B-015: "jump to what's playing" tap target — `⊙` in fgPrimary at rowSize
  /// (B-033 contrast bump), 44×44 hit target (B-013).
  Widget _buildJumpGlyph(
    AppPalette palette,
    AppTypography typography,
    String playingPath,
  ) =>
      _glyphButton(
        semanticsLabel: 'jump to now-playing folder',
        buttonKey: const ValueKey('void-crumb-jump-to-playing'),
        onTap: () => _jumpToNowPlaying(playingPath),
        box: 44,
        glyph: '⊙', // ⊙ — CIRCLED DOT OPERATOR
        style:
            _mono(typography, palette.fgPrimary, typography.rowSize, height: 1),
      );

  Widget _buildSearchCrumb(AppPalette palette, AppTypography typography) {
    // B-013: input at row-size; × keeps tertiary tone at crumbSize with a 44 px
    // hit target; row accepts a downward swipe as dismissal.
    final textStyle = _mono(typography, palette.fgPrimary, typography.rowSize);
    return GestureDetector(
      key: const ValueKey('void-search-crumb-region'),
      behavior: HitTestBehavior.opaque,
      // Downward fling dismisses (mirrors × tap); TextField keeps scroll/long-press.
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 200) _exitSearchMode();
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('? ', style: textStyle.copyWith(color: palette.fgSecondary)),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              // autofocus is the single keyboard trigger; requestFocus raced
              // the expand rebuild and flashed the keyboard.
              autofocus: true,
              cursorColor: palette.fgPrimary,
              cursorWidth: 1,
              style: textStyle,
              decoration: const InputDecoration.collapsed(hintText: ''),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _exitSearchMode(),
            ),
          ),
          _glyphButton(
            semanticsLabel: 'close search',
            buttonKey: const ValueKey('void-search-close'),
            onTap: _exitSearchMode,
            box: 44,
            glyph: '×',
            style:
                _mono(typography, palette.fgTertiary, typography.crumbSize),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressHairline(AppPalette palette) {
    final si = context.watch<AudioPlayerProvider>().songInfo;
    final position = si?.position ?? 0;
    final duration = si?.duration ?? 0;
    final fraction = duration <= 0 ? 0.0 : (position / duration).clamp(0.0, 1.0);
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

  Widget _buildSettingsButton(AppPalette palette, AppTypography typography) {
    // B-004: 48 dp tap target with a perceptible glyph.
    return Positioned(
      top: 4,
      right: 4,
      child: _glyphButton(
        semanticsLabel: 'settings',
        buttonKey: const ValueKey('void-settings-button'),
        onTap: () => VoidSettingsSheet.push(context),
        box: 48,
        glyph: '⋮', // U+22EE VERTICAL ELLIPSIS — readable in mono
        style: _mono(typography, palette.fgPrimary.withAlpha(180),
            typography.rowSize + 4,
            height: 1),
      ),
    );
  }

  Widget _buildSwipeUpHint(AppPalette palette, AppTypography typography) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onHeroVerticalDrag,
      onVerticalDragEnd: _onHeroVerticalDragEnd,
      child: PressFeedback(
        onTap: () => _setBrowserExpanded(true),
        child: Container(
          alignment: Alignment.center,
          child: Text(
            '↑ swipe to browse',
            style: _mono(typography, palette.fgTertiary, typography.hintSize,
                letterSpacing: 0.2),
          ),
        ),
      ),
    );
  }

  Widget _buildHint(AppPalette palette, AppTypography typography) {
    if (!_showHint) return const SizedBox.shrink();
    return Positioned(
      top: 12,
      right: 14,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _hintFaded ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 800),
          child: Text(
            'tap · long-press · swipe',
            style: _mono(typography, palette.fgQuaternary, typography.hintSize,
                letterSpacing: 0.18),
          ),
        ),
      ),
    );
  }
}

/// Per-frame layout metrics computed by [_VoidScreenState._layout].
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
