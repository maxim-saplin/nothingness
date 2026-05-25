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
import '../testing/agent_service.dart';
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

/// Home shell for all four visualisations (the Void chrome).
///
/// Layout (top → bottom):
///   * Hero (~32% viewport height) — `heroFor(screenConfig.type)`.
///   * Tree — embedded [VoidBrowser].
///   * Transport — three-button row above the crumb.
///   * Crumb — single-line current-path readout (morphs to a search input).
///   * Progress hairline — 1 px bottom edge tracking position / duration.
///
/// Hero gestures:
///   * Tap → toggle play/pause.
///   * Horizontal swipe left (> 40 px) → previous track.
///   * Horizontal swipe right → next track.
///
/// Immersive mode hides the browser / transport / crumb / progress and
/// scales the hero to fill the screen. Driven by
/// [SettingsService.immersiveNotifier] — there is no longer a drag-down
/// gesture (replaced by a settings toggle).
class VoidScreen extends StatefulWidget {
  const VoidScreen({
    super.key,
    this.config,
    this.settings,
    this.libraryController,
  });

  /// Active visualisation config; falls back to the value in
  /// [SettingsService.screenConfigNotifier] when null (legacy callers).
  final ScreenConfig? config;

  /// Spectrum settings forwarded to the spectrum hero.
  final SpectrumSettings? settings;

  /// Optional externally-owned [LibraryController]. When supplied the
  /// screen does NOT create or dispose its own controller — used by tests
  /// to pre-seed `currentPath` / `tracks` without touching the real
  /// MediaStore or filesystem (B-015 jump-to-now-playing tests).
  final LibraryController? libraryController;

  @override
  State<VoidScreen> createState() => _VoidScreenState();
}

class _VoidScreenState extends State<VoidScreen>
    with TickerProviderStateMixin {
  late final LibraryController _libraryController;
  late final bool _ownsLibraryController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final AnimationController _immersiveCtrl;
  late final Animation<double> _immersiveT;
  // B-033: drives the swipe-up browser's slide-in / slide-out. Held at 1.0
  // for non-swipe-up presentations (browser is always present). For
  // swipe-up: 0 = parked offscreen below the viewport, 1 = fully resting
  // at its normal position. Hero height + browser top/bottom interpolate
  // off this single controller so they can never disagree mid-frame.
  // Non-final to survive hot reload — initialized in initState.
  late AnimationController _browserSlideCtrl;
  late Animation<double> _browserSlideT;
  final SettingsService _settings = SettingsService();
  bool _immersive = false;
  TransportPosition _transportPosition = TransportPosition.bottom;
  BrowserPresentation _browserPresentation = BrowserPresentation.fixed;
  bool _browserExpanded = false;
  double _swipeUpAccum = 0;
  String? _lastPersistedPath;
  bool _showHint = false;
  bool _hintFaded = false;
  bool _searchMode = false;
  double _horizDragAccum = 0;
  // B-027: latched while the current horizontal drag has already produced a
  // prev/next event (either via the 60-dp distance accumulator below or via
  // the velocity escape in `_onHeroHorizontalDragEnd`). Prevents the end-of-
  // gesture velocity check from re-firing on top of a distance trip.
  bool _horizDragFired = false;
  Timer? _hintFadeTimer;
  // B-031: hide-only debounce for the crumb's `⊙` jump glyph. The crumb
  // rebuilds on every library/playback notification, and there is a brief
  // race during track changes where `dirname(songInfo.path) == currentPath`
  // for a frame or two even though the glyph should still be available.
  //
  // Mechanism: `_jumpGlyphLatched` reflects what the user sees right now.
  // Each rebuild evaluates the raw divergence predicate. If true → latched
  // true (immediate) and any pending hide timer is cancelled. If false →
  // schedule a hide timer for [_jumpGlyphHideDebounce] from now (resetting
  // any prior timer). The latch only flips to false when the timer fires,
  // so a one-frame race never collapses the glyph.
  bool _jumpGlyphLatched = false;
  Timer? _jumpGlyphHideTimer;
  static const Duration _jumpGlyphHideDebounce = Duration(milliseconds: 200);
  // B-012: GlobalKey on the hero feedback surface so horizontal-drag
  // accumulator (which lives in this state) can fire the directional
  // swipe flash exactly when prev/next actually triggers.
  final GlobalKey<HeroFeedbackSurfaceState> _heroFeedbackKey =
      GlobalKey<HeroFeedbackSurfaceState>();
  // B-015: GlobalKey on the embedded VoidBrowser so the crumb's
  // jump-to-now-playing tap can drive `scrollToTrack` on the browser's
  // shared ScrollController after `loadFolder` settles.
  final GlobalKey<VoidBrowserState> _browserKey =
      GlobalKey<VoidBrowserState>();

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
    if (_ownsLibraryController) {
      _bootstrapLibrary();
    }
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    // A single controller drives BOTH the hero growth and the
    // browser/crumb collapse so they sum to the available height at every
    // frame — no layout-time overflow (B-003 fix).
    _immersiveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _immersiveT = CurvedAnimation(
      parent: _immersiveCtrl,
      curve: Curves.easeOutCubic,
    );
    // B-033: 280 ms easeOutCubic — close to MaterialPageRoute's default
    // feel (the settings sheet uses MaterialPageRoute) but a touch
    // snappier so the swipe-up gesture feels responsive.
    _browserSlideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _browserSlideT = CurvedAnimation(
      parent: _browserSlideCtrl,
      curve: Curves.easeOutCubic,
    );
    _immersive = _settings.immersiveNotifier.value;
    _transportPosition = _settings.transportPositionNotifier.value;
    _browserPresentation = _settings.browserPresentationNotifier.value;
    if (_immersive) _immersiveCtrl.value = 1.0;
    // For non-swipe-up presentations (fixed) the browser is always at rest
    // (t=1). For swipe-up, start collapsed (t=0) until the user expands it.
    _browserSlideCtrl.value =
        _browserPresentation == BrowserPresentation.swipeUp ? 0.0 : 1.0;
    _settings.immersiveNotifier.addListener(_onImmersiveChanged);
    _settings.transportPositionNotifier.addListener(_onTransportPositionChanged);
    _settings.browserPresentationNotifier
        .addListener(_onBrowserPresentationChanged);
    _settings.screenConfigNotifier.addListener(_onScreenConfigChanged);
    // The PopScope's `canPop` is computed from `currentPath`, so we have to
    // re-evaluate it whenever the library navigates.
    _libraryController.addListener(_onLibraryChanged);
    _maybeShowLaunchHint();

    // Expose controller + immersive flag to the VM-service agent surface.
    AgentService.registerLibraryController(_libraryController);
    AgentService.registerImmersiveLookup(() => _immersive);
  }

  void _onImmersiveChanged() {
    final next = _settings.immersiveNotifier.value;
    if (_immersive == next) return;
    setState(() => _immersive = next);
    if (next) {
      _immersiveCtrl.forward();
    } else {
      _immersiveCtrl.reverse();
    }
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
      // Reset the expansion flag whenever the mode changes so the user
      // sees the canonical state for the newly-selected presentation.
      _browserExpanded = false;
    });
    // B-033: keep the slide controller aligned with the new mode.
    //   * fixed → browser always at rest (t=1).
    //   * swipeUp → start collapsed (t=0), expand on user gesture.
    if (next == BrowserPresentation.swipeUp) {
      _browserSlideCtrl.value = 0.0;
    } else {
      _browserSlideCtrl.value = 1.0;
    }
  }

  void _onLibraryChanged() {
    if (!mounted) return;
    // Lightweight rebuild to refresh PopScope.canPop when currentPath
    // changes. Child widgets that listen via Provider get their own
    // notifications and don't depend on this setState.
    setState(() {});
    // Persist navigation so the next launch returns to the same folder.
    final path = _libraryController.currentPath;
    if (path != _lastPersistedPath) {
      _lastPersistedPath = path;
      _settings.saveLastLibraryPath(path);
    }
  }

  /// Owns the controller's first init + the one-shot restoration of the
  /// last browsed path. Kept inside [VoidScreen] (rather than [VoidBrowser])
  /// because the controller is supplied externally and the parent is the
  /// natural place to sequence "init, then restore".
  Future<void> _bootstrapLibrary() async {
    await _libraryController.init();
    if (!mounted) return;
    final saved = await _settings.loadLastLibraryPath();
    if (!mounted) return;
    if (saved == null || saved.isEmpty) return;
    if (_libraryController.currentPath == saved) return;
    // Record the path we are about to navigate to so the listener does
    // not turn around and re-persist the same value we just loaded.
    _lastPersistedPath = saved;
    try {
      await _libraryController.loadFolder(saved);
    } catch (_) {
      // Folder may have disappeared (SD card pulled, etc.) — fall back
      // to whatever loadRoot() landed on and clear the stale pointer.
      await _settings.saveLastLibraryPath(null);
    }
  }

  void _onScreenConfigChanged() {
    // The hero dispatcher reads SettingsService when widget.config is null;
    // a setState here picks up changes from settings cycle-rows without a
    // parent rebuild.
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _hintFadeTimer?.cancel();
    _jumpGlyphHideTimer?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _settings.immersiveNotifier.removeListener(_onImmersiveChanged);
    _settings.transportPositionNotifier
        .removeListener(_onTransportPositionChanged);
    _settings.browserPresentationNotifier
        .removeListener(_onBrowserPresentationChanged);
    _settings.screenConfigNotifier.removeListener(_onScreenConfigChanged);
    _libraryController.removeListener(_onLibraryChanged);
    _immersiveCtrl.dispose();
    _browserSlideCtrl.dispose();
    AgentService.registerImmersiveLookup(null);
    AgentService.registerLibraryController(null);
    if (_ownsLibraryController) {
      _libraryController.dispose();
    }
    super.dispose();
  }

  void _onSearchFocusChanged() {
    // B-013: collapse on focus-out regardless of query. Tap-away ends the
    // session; re-tapping the crumb resumes a fresh search. Previously
    // this only collapsed when the query was empty, which left a stale
    // input lingering after dismissal gestures (drag, settings tap, etc.).
    if (!_searchFocusNode.hasFocus && _searchMode) {
      setState(() => _searchMode = false);
      // Keep _searchController text intact for the next session if the
      // dismissal was a focus loss without explicit clear — but the
      // results panel keys off the controller, so empty it to mirror the
      // visual collapse. _exitSearchMode already does this; mirror it here.
      _searchController.clear();
      // B-014: restore the queue captured at the start of this search
      // session, if any. No-op when the user never tapped a result.
      _endSearchSession();
    }
  }

  void _enterSearchMode() {
    setState(() => _searchMode = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _exitSearchMode() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() => _searchMode = false);
    // B-014: restore the prior queue. The provider/controller handle the
    // no-active-session case as a no-op.
    _endSearchSession();
  }

  void _endSearchSession() {
    if (!mounted) return;
    // Fire-and-forget: the controller / provider treats no-active-session
    // as a no-op, and we don't need to block UI on the restore.
    final player = context.read<AudioPlayerProvider>();
    unawaited(player.exitSearchSession());
  }

  void _maybeShowLaunchHint() {
    // Shown on every cold launch (and every screen mount); fades after 3 s.
    // Pre-fix this persisted a flag and never showed again — see B-005.
    if (!mounted) return;
    setState(() {
      _showHint = true;
      _hintFaded = false;
    });
    _hintFadeTimer?.cancel();
    _hintFadeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _hintFaded = true);
    });
  }

  /// Velocity threshold (px/s) for the B-027 escape hatch. A short flick
  /// whose distance never crosses [_horizDistanceThreshold] still fires
  /// prev/next if its end velocity exceeds this value. Tuned to match
  /// PageView's flick feel — anything noticeably faster than a casual drag.
  static const double _horizVelocityThreshold = 300.0;
  static const double _horizDistanceThreshold = 60.0;

  void _onHeroHorizontalDrag(DragUpdateDetails d) {
    _horizDragAccum += d.primaryDelta ?? 0;
    final player = context.read<AudioPlayerProvider>();
    if (_horizDragAccum > _horizDistanceThreshold) {
      // Right-ward swipe → next track.
      player.next();
      _heroFeedbackKey.currentState?.flashSwipe(1);
      _horizDragAccum = 0;
      _horizDragFired = true;
    } else if (_horizDragAccum < -_horizDistanceThreshold) {
      // Left-ward swipe → previous track.
      player.previous();
      _heroFeedbackKey.currentState?.flashSwipe(-1);
      _horizDragAccum = 0;
      _horizDragFired = true;
    }
  }

  /// B-027: velocity escape. If the gesture ended without crossing the
  /// 60-dp distance threshold but the user clearly flicked (|v| > 300 px/s),
  /// fire prev/next based on the sign of the velocity. The `_horizDragFired`
  /// guard prevents a long+fast drag from double-firing (once on distance,
  /// once on velocity).
  void _onHeroHorizontalDragEnd(DragEndDetails d) {
    if (!_horizDragFired) {
      final v = d.primaryVelocity ?? 0;
      if (v.abs() > _horizVelocityThreshold) {
        final player = context.read<AudioPlayerProvider>();
        if (v > 0) {
          player.next();
          _heroFeedbackKey.currentState?.flashSwipe(1);
        } else {
          player.previous();
          _heroFeedbackKey.currentState?.flashSwipe(-1);
        }
      }
    }
    _horizDragAccum = 0;
    _horizDragFired = false;
  }

  /// Upward drag on the (expanded) hero while the swipe-up browser is
  /// collapsed mirrors the hint-band gesture: 30 px past the threshold
  /// flips `_browserExpanded` so the user can swipe anywhere in the
  /// freed area, not just the thin strip above the crumb.
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

  void _onHeroVerticalDragEnd(DragEndDetails _) {
    _swipeUpAccum = 0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final geometry = Theme.of(context).extension<AppGeometry>()!;
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
              // B-033: a single AnimatedBuilder listens to BOTH the
              // immersive ramp and the swipe-up slide. Hero height +
              // browser top/bottom interpolate off `s` (slide 0..1) so the
              // hero growth and browser slide can never drift apart
              // mid-frame.
              return AnimatedBuilder(
                animation: Listenable.merge([_immersiveT, _browserSlideT]),
                builder: (context, _) {
                  final t = _immersiveT.value;
                  final s = _browserPresentation ==
                          BrowserPresentation.swipeUp
                      ? _browserSlideT.value
                      : 1.0;
                  // reservedBottom shrinks to 0 in immersive so the hero
                  // meets the screen edge; otherwise it pushes the crumb +
                  // hairline above the Android gesture-nav bar (B-002).
                  final reservedBottom = bottomInset * (1 - t);
                  final showChildren = t < 0.999;
                  // B-018 per-skin transport contract: hosted heroes
                  // (Spectrum, Dot, Void) opt-in to chrome-owned transport
                  // placement; bespoke heroes (Polo) opt-out and paint
                  // their own controls. The shell suppresses the row
                  // entirely when the active hero is bespoke, regardless
                  // of the global transport setting.
                  final activeConfig = _resolvedScreenConfig();
                  final hostsTransport = activeConfig.hostsChromeTransport;
                  // Transport pins to either the top of the browser band
                  // (just below the hero) or to the bottom (just above the
                  // crumb), or it's hidden. The browser's vertical slot
                  // shrinks from whichever side the strip claims.
                  final isTransportTop = hostsTransport &&
                      _transportPosition == TransportPosition.top;
                  final isTransportBottom = hostsTransport &&
                      _transportPosition == TransportPosition.bottom;
                  final hasTransport = isTransportTop || isTransportBottom;
                  final browserBottom = reservedBottom +
                      _crumbHeight +
                      (isTransportBottom ? _transportHeight : 0.0);
                  // The hero takes one of two non-immersive shapes:
                  //   * EXPANDED (s=1): the canonical `heroHeight`. The
                  //     browser is at rest occupying the rest of the band.
                  //   * COLLAPSED (s=0): the hero grows down to claim the
                  //     freed browser slot, leaving only the hint band.
                  // For 0<s<1 we lerp between the two so the slide reads
                  // as a single coherent motion (B-033).
                  final double heroHCollapsed = availableH -
                      browserBottom -
                      _swipeHintZoneHeight -
                      (isTransportTop ? _transportHeight : 0.0);
                  final double heroHExpanded = heroHeight;
                  final double baseHeroH =
                      heroHCollapsed + (heroHExpanded - heroHCollapsed) * s;
                  // Hero height interpolates from `baseHeroH` (non-
                  // immersive) to the full available height (immersive).
                  // Everything else hangs off the bottom edge so the
                  // hero growth never collides with their fixed slot
                  // (B-003: no layout-time overflow mid-transition).
                  final heroH = baseHeroH + (availableH - baseHeroH) * t;
                  // Browser top/bottom slide together. At s=1 the browser
                  // rests under the hero (or top transport). At s=0 the
                  // whole browser is parked offscreen below the viewport
                  // — its top sits at availableH (the bottom edge) and
                  // its bottom sits one browser-height below that.
                  final double restingBrowserTop =
                      heroHExpanded + (isTransportTop ? _transportHeight : 0.0);
                  final double restingBrowserBottom = browserBottom;
                  // Height of the browser at rest — used to extend the
                  // bottom anchor offscreen by the same amount as the top.
                  final double restingBrowserHeight = (availableH -
                          restingBrowserTop -
                          restingBrowserBottom)
                      .clamp(0.0, availableH);
                  final double parkedTop = availableH;
                  final double parkedBottom = -restingBrowserHeight;
                  final double browserTop =
                      parkedTop + (restingBrowserTop - parkedTop) * s;
                  final double browserBottomAnimated = parkedBottom +
                      (restingBrowserBottom - parkedBottom) * s;
                  // Hint band is only meaningful while the browser is
                  // (mostly) collapsed in swipe-up mode. Fade it out as
                  // the slide progresses so it doesn't crash into the
                  // incoming browser chrome.
                  final bool swipeUp = _browserPresentation ==
                      BrowserPresentation.swipeUp;
                  final double hintOpacity =
                      swipeUp ? (1.0 - s).clamp(0.0, 1.0) : 0.0;
                  return Stack(
                    children: [
                      // Hero — anchored top, animated height. Wrapped in a
                      // gesture surface that owns tap (play/pause) and
                      // horizontal swipe (prev/next).
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: heroH,
                        child: _buildHeroGestureSurface(
                          child: _buildHeroFor(_resolvedScreenConfig()),
                        ),
                      ),
                      // Browser — always rendered (B-033) so the slide
                      // animation always has a target. Parked offscreen
                      // when collapsed; slides up into its resting slot as
                      // `s` ramps to 1. Wrapped in IgnorePointer at s≈0 so
                      // the parked browser can't intercept stray touches.
                      if (showChildren)
                        Positioned(
                          top: browserTop,
                          left: 0,
                          right: 0,
                          bottom: browserBottomAnimated,
                          child: IgnorePointer(
                            ignoring: s < 0.01,
                            child: ClipRect(
                              clipBehavior: Clip.hardEdge,
                              child: VoidBrowser(
                                key: _browserKey,
                                controller: _libraryController,
                                searchController: _searchController,
                                // B-032: swipe-up presentation gives the
                                // browser a drag-down close affordance.
                                // Fixed presentation keeps the browser
                                // anchored — no handle, no close gesture.
                                isDismissable: swipeUp && _browserExpanded,
                                onDragDownClose: _collapseSwipeUpBrowser,
                              ),
                            ),
                          ),
                        ),
                      // Swipe-up hint band — a thin strip at the bottom
                      // of the freed browser slot. The expanded hero sits
                      // directly above it. Tap / upward drag expands the
                      // browser into view. Fades out (B-033) as the
                      // browser slides up into its place.
                      if (showChildren && swipeUp && hintOpacity > 0.001)
                        Positioned(
                          left: 0,
                          right: 0,
                          height: _swipeHintZoneHeight,
                          bottom: browserBottom,
                          child: IgnorePointer(
                            ignoring: _browserExpanded,
                            child: Opacity(
                              opacity: hintOpacity,
                              child:
                                  _buildSwipeUpHint(palette, typography),
                            ),
                          ),
                        ),
                      // Transport row — top (just below hero) or bottom
                      // (just above crumb). Hidden in immersive or when
                      // position == off.
                      if (showChildren && hasTransport)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: isTransportTop ? heroH : null,
                          bottom: isTransportBottom
                              ? reservedBottom + _crumbHeight
                              : null,
                          height: _transportHeight,
                          child: const TransportRow(),
                        ),
                      // Crumb — anchored above the gesture-nav bar.
                      if (showChildren)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: reservedBottom,
                          height: _crumbHeight,
                          child: _buildCrumb(palette, typography, geometry),
                        ),
                      // Settings button — top-right, hidden in immersive.
                      if (showChildren)
                        _buildSettingsButton(palette, typography),
                      // Cold-launch gesture hint — always above everything.
                      _buildHint(palette, typography),
                      // Progress hairline — at the bottom, above the
                      // gesture-nav bar in non-immersive (B-002).
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: reservedBottom,
                        child: _buildProgressHairline(palette),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
      ),
    );
  }

  /// B-032: collapse the swipe-up browser. Mirrors the back-button branch
  /// of [_onPopInvoked] so the drag-down close gesture and Android back
  /// converge on a single code path. No-op outside the swipe-up presentation.
  void _collapseSwipeUpBrowser() {
    if (!mounted) return;
    if (_browserPresentation != BrowserPresentation.swipeUp) return;
    if (!_browserExpanded) return;
    _setBrowserExpanded(false);
  }

  /// B-033: single entry point for flipping `_browserExpanded`. Calls
  /// [setState] and drives [_browserSlideCtrl] in the matching direction so
  /// the slide animation stays in lockstep with the boolean state. All
  /// other code paths that want to expand / collapse the swipe-up browser
  /// go through here.
  void _setBrowserExpanded(bool next) {
    if (_browserExpanded == next) return;
    setState(() => _browserExpanded = next);
    if (next) {
      _browserSlideCtrl.forward();
    } else {
      _browserSlideCtrl.reverse();
    }
  }

  /// Android back: collapse the swipe-up browser, then exit search, then
  /// walk one folder up the library tree. Only when all three are
  /// exhausted does PopScope let the pop through and the OS leave the app.
  void _onPopInvoked(bool didPop, Object? _) {
    if (didPop) return;
    if (_browserExpanded &&
        _browserPresentation == BrowserPresentation.swipeUp) {
      _setBrowserExpanded(false);
      return;
    }
    if (_searchMode) {
      _exitSearchMode();
      return;
    }
    if (_libraryController.currentPath != null) {
      _libraryController.navigateUp();
      return;
    }
  }

  /// Fixed slot height for the crumb (path readout / search input).
  static const double _crumbHeight = 56.0;

  /// Fixed slot height for the transport row — seek strip + icon row.
  /// Kept in sync with [TransportRow.transportHeight].
  static const double _transportHeight = TransportRow.transportHeight;

  /// Height of the swipe-up hint band when the browser is collapsed in
  /// swipe-up mode. The hero claims everything above this band so the
  /// visualisation has room to breathe instead of stranding empty space.
  static const double _swipeHintZoneHeight = 56.0;

  /// Resolve the active visualisation config. Prefer the value passed via
  /// the constructor (used by tests and by [MediaControllerPage]), falling
  /// back to [SettingsService.screenConfigNotifier] for legacy callers.
  ScreenConfig _resolvedScreenConfig() =>
      widget.config ?? _settings.screenConfigNotifier.value;

  /// Map the active screen type onto its hero widget. The hero is purely
  /// the visualisation — gestures and chrome live in the surrounding
  /// Void shell.
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

  /// Wraps the hero in a gesture surface so tap / horizontal-swipe drive
  /// the player regardless of which visualisation is rendered inside.
  /// Vertical drag is wired only when the swipe-up browser is collapsed —
  /// the same arena where the hint band lives.
  ///
  /// B-012: the surface also paints a tap-ring at the touch point and a
  /// directional flash when a horizontal swipe trips prev / next, so taps
  /// and swipes get immediate visual feedback instead of waiting on
  /// downstream state changes.
  Widget _buildHeroGestureSurface({required Widget child}) {
    final player = context.read<AudioPlayerProvider>();
    final bool acceptVertical =
        _browserPresentation == BrowserPresentation.swipeUp &&
            !_browserExpanded;
    return HeroFeedbackSurface(
      key: _heroFeedbackKey,
      onTap: () => player.playPause(),
      onHorizontalDragUpdate: _onHeroHorizontalDrag,
      onHorizontalDragEnd: _onHeroHorizontalDragEnd,
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
    // Mirrors v6_monk's #crumb: a path readout that morphs into "? <query>|"
    // when long-pressed. The hidden TextField captures keystrokes while in
    // search mode; tapping outside or clearing the query collapses back.
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.divider, width: geometry.dividerThickness),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _searchMode ? null : _enterSearchMode,
        onTap: _searchMode ? null : null,
        child: Builder(
          builder: (context) {
            if (_searchMode) {
              // Search crumb keeps its own 12-px vertical padding; the
              // input + close glyph self-size around it.
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: _buildSearchCrumb(palette, typography),
              );
            }
            LibraryController? controller;
            try {
              controller = Provider.of<LibraryController>(context, listen: true);
            } catch (_) {
              controller = null;
            }
            final path = controller?.currentPath;
            final crumbStyle = TextStyle(
              color: palette.fgSecondary,
              fontFamily: typography.monoFamily,
              fontSize: typography.crumbSize,
            );
            // B-015: render the jump-to-now-playing glyph when the playing
            // track lives outside the currently-browsed folder.
            //
            // B-031: hide-only debounce. The crumb rebuilds on every
            // library/playback notification and `currentPath` / `songInfo`
            // can briefly agree mid-track-change. We treat the "should-be-
            // visible" predicate as authoritative and only allow the glyph
            // to flip to hidden once the predicate has been false for
            // ~200 ms. A timer schedules a rebuild when the window expires
            // so a genuine match still hides the glyph after the debounce.
            final player = context.watch<AudioPlayerProvider>();
            final playingPath = player.songInfo?.track.path;
            final divergent = playingPath != null &&
                playingPath.isNotEmpty &&
                p.dirname(playingPath) != (path ?? '');
            final showJumpGlyph = _resolveJumpGlyphVisible(divergent);
            // The path readout keeps its 12-px vertical padding to preserve
            // the existing crumb baseline; the 44×44 glyph hit target lives
            // outside that padding so it can extend to the row edges and
            // satisfy the Material minimum (matches B-013's × pattern).
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 0, 12),
                    child: MidEllipsis(
                      text: path == null || path.isEmpty ? '~' : path,
                      style: crumbStyle,
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

  /// B-015: tap target for "take me to what's playing right now".
  ///
  /// The glyph is `⊙` in `fgPrimary` at `rowSize`. The hit target is a 44×44
  /// square so the control matches B-013's accessibility-minimum pattern.
  /// Visible only when `dirname(playingPath) != currentPath` — the parent
  /// decides; this widget just renders the affordance and wires the tap.
  ///
  /// B-033: bumped from `crumbSize` / `fgSecondary` to `rowSize` /
  /// `fgPrimary`. On a real device the previous styling was nearly
  /// invisible against the dark chrome.
  Widget _buildJumpGlyph(
    AppPalette palette,
    AppTypography typography,
    String playingPath,
  ) {
    return Semantics(
      label: 'jump to now-playing folder',
      button: true,
      child: PressFeedback(
        key: const ValueKey('void-crumb-jump-to-playing'),
        onTap: () => _jumpToNowPlaying(playingPath),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(
              '⊙', // ⊙ — CIRCLED DOT OPERATOR
              style: TextStyle(
                color: palette.fgPrimary,
                fontFamily: typography.monoFamily,
                fontSize: typography.rowSize,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// B-031: source-of-truth for the crumb glyph's visibility. Returns the
  /// latched flag; flips it eagerly to `true` whenever the underlying
  /// [divergent] predicate is true, and only flips it back to `false` once
  /// the predicate has been false continuously for
  /// [_jumpGlyphHideDebounce] (~200 ms). This filters out one-frame races
  /// between `library.currentPath` and `playback.songInfo` updates around
  /// track changes.
  bool _resolveJumpGlyphVisible(bool divergent) {
    if (divergent) {
      _jumpGlyphHideTimer?.cancel();
      _jumpGlyphHideTimer = null;
      _jumpGlyphLatched = true;
      return true;
    }
    if (!_jumpGlyphLatched) return false;
    // Predicate is false but the latch is still true — schedule (or keep)
    // a hide timer. We only arm a fresh timer if none is pending so the
    // window doesn't keep getting reset by ordinary rebuilds.
    _jumpGlyphHideTimer ??= Timer(_jumpGlyphHideDebounce, () {
      _jumpGlyphHideTimer = null;
      if (!mounted) return;
      setState(() => _jumpGlyphLatched = false);
    });
    return true;
  }

  /// Duration of the swipe-up browser open animation. Must stay in sync
  /// with [_browserExpanded] state changes: there's no explicit slide-in
  /// animation; the browser swaps in atomically when `_browserExpanded`
  /// flips, but we still await a short window so the new VoidBrowser has a
  /// chance to mount and lay out its first frame before we navigate +
  /// scroll. ~250 ms keeps the interaction reading as a single gesture.
  static const Duration _browserOpenSettleDuration =
      Duration(milliseconds: 250);

  /// B-015 / B-031: navigate the browser to [playingPath]'s parent folder
  /// and centre the now-playing row in view. The sequence:
  ///
  ///   1. If the browser is in swipe-up presentation AND dismissed, open it
  ///      first and wait one settle window so its first frame is laid out.
  ///   2. `loadFolder(parent)` if we aren't already there.
  ///   3. Pump frames until the target row's `GlobalKey.currentContext` is
  ///      non-null OR ~500 ms have elapsed (lazy-built lists may need a few
  ///      frames before the SliverList builds the target row).
  ///   4. Centre the row via `Scrollable.ensureVisible`. If the row never
  ///      built, fall back to `ScrollController.animateTo(index * rowHeight)`
  ///      so the user sees SOMETHING happen even for very long folders.
  Future<void> _jumpToNowPlaying(String playingPath) async {
    final parent = p.dirname(playingPath);
    if (parent.isEmpty) return;
    // B-031 step 1: open the swipe-up browser if it's currently dismissed.
    if (_browserPresentation == BrowserPresentation.swipeUp &&
        !_browserExpanded) {
      _setBrowserExpanded(true);
      await Future<void>.delayed(_browserOpenSettleDuration);
      if (!mounted) return;
    }
    if (_libraryController.currentPath != parent) {
      await _libraryController.loadFolder(parent);
    }
    if (!mounted) return;
    await _browserKey.currentState?.scrollToTrack(playingPath);
  }

  Widget _buildSearchCrumb(AppPalette palette, AppTypography typography) {
    // B-013: input renders at row-size (visual parity with the result rows
    // above), the × glyph keeps its tertiary tone but ships with a 44 px
    // square hit target, and the whole row accepts a downward swipe as a
    // dismissal gesture.
    final textStyle = TextStyle(
      color: palette.fgPrimary,
      fontFamily: typography.monoFamily,
      fontSize: typography.rowSize,
    );
    // The × glyph itself stays at the same visual weight as before
    // (typography.crumbSize, fgTertiary). Only its hit target grows.
    final closeGlyphStyle = TextStyle(
      color: palette.fgTertiary,
      fontFamily: typography.monoFamily,
      fontSize: typography.crumbSize,
    );
    return GestureDetector(
      key: const ValueKey('void-search-crumb-region'),
      behavior: HitTestBehavior.opaque,
      // Downward fling / drag dismisses the search session, mirroring the
      // × tap. We only act on a meaningfully-downward gesture so the
      // TextField still gets to own intra-text scroll/long-press.
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 200) _exitSearchMode();
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('? ',
              style: textStyle.copyWith(color: palette.fgSecondary)),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              cursorColor: palette.fgPrimary,
              cursorWidth: 1,
              style: textStyle,
              decoration: const InputDecoration.collapsed(hintText: ''),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _exitSearchMode(),
            ),
          ),
          Semantics(
            label: 'close search',
            button: true,
            child: PressFeedback(
              key: const ValueKey('void-search-close'),
              onTap: _exitSearchMode,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Text('×', style: closeGlyphStyle),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressHairline(AppPalette palette) {
    final player = context.watch<AudioPlayerProvider>();
    final si = player.songInfo;
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
    // 48 dp tap target with a perceptible glyph (B-004). Pre-fix this was a
    // ~36 dp `·` rendered in fgTertiary — unreachable on the first try.
    return Positioned(
      top: 4,
      right: 4,
      child: Semantics(
        label: 'settings',
        button: true,
        child: PressFeedback(
          key: const ValueKey('void-settings-button'),
          onTap: () => VoidSettingsSheet.push(context),
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: Text(
              '⋮', // U+22EE VERTICAL ELLIPSIS — readable in mono
              style: TextStyle(
                color: palette.fgPrimary.withAlpha(180),
                fontFamily: typography.monoFamily,
                fontSize: typography.rowSize + 4,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeUpHint(AppPalette palette, AppTypography typography) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        _swipeUpAccum += d.primaryDelta ?? 0;
        if (_swipeUpAccum < -30 && !_browserExpanded) {
          _setBrowserExpanded(true);
          _swipeUpAccum = 0;
        }
      },
      onVerticalDragEnd: (_) => _swipeUpAccum = 0,
      child: PressFeedback(
        onTap: () => _setBrowserExpanded(true),
        child: Container(
          alignment: Alignment.center,
          child: Text(
            '↑ swipe to browse',
            style: TextStyle(
              color: palette.fgTertiary,
              fontFamily: typography.monoFamily,
              fontSize: typography.hintSize,
              letterSpacing: 0.2,
            ),
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
            style: TextStyle(
              color: palette.fgQuaternary,
              fontFamily: typography.monoFamily,
              fontSize: typography.hintSize,
              letterSpacing: 0.18,
            ),
          ),
        ),
      ),
    );
  }
}
