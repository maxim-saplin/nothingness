import 'dart:async';

import 'package:flutter/material.dart';
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
  const VoidScreen({super.key, this.config, this.settings});

  /// Active visualisation config; falls back to the value in
  /// [SettingsService.screenConfigNotifier] when null (legacy callers).
  final ScreenConfig? config;

  /// Spectrum settings forwarded to the spectrum hero.
  final SpectrumSettings? settings;

  @override
  State<VoidScreen> createState() => _VoidScreenState();
}

class _VoidScreenState extends State<VoidScreen>
    with SingleTickerProviderStateMixin {
  late final LibraryController _libraryController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final AnimationController _immersiveCtrl;
  late final Animation<double> _immersiveT;
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
  Timer? _hintFadeTimer;
  // B-012: GlobalKey on the hero feedback surface so horizontal-drag
  // accumulator (which lives in this state) can fire the directional
  // swipe flash exactly when prev/next actually triggers.
  final GlobalKey<HeroFeedbackSurfaceState> _heroFeedbackKey =
      GlobalKey<HeroFeedbackSurfaceState>();

  @override
  void initState() {
    super.initState();
    _libraryController = LibraryController(
      libraryBrowser: LibraryBrowser(
        supportedExtensions: AudioPlayerProvider.supportedExtensions,
      ),
      libraryService: LibraryService(),
    );
    _bootstrapLibrary();
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
    _immersive = _settings.immersiveNotifier.value;
    _transportPosition = _settings.transportPositionNotifier.value;
    _browserPresentation = _settings.browserPresentationNotifier.value;
    if (_immersive) _immersiveCtrl.value = 1.0;
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
    AgentService.registerImmersiveLookup(null);
    AgentService.registerLibraryController(null);
    _libraryController.dispose();
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

  void _onHeroHorizontalDrag(DragUpdateDetails d) {
    _horizDragAccum += d.primaryDelta ?? 0;
    final player = context.read<AudioPlayerProvider>();
    if (_horizDragAccum > 60) {
      // Right-ward swipe → next track.
      player.next();
      _heroFeedbackKey.currentState?.flashSwipe(1);
      _horizDragAccum = 0;
    } else if (_horizDragAccum < -60) {
      // Left-ward swipe → previous track.
      player.previous();
      _heroFeedbackKey.currentState?.flashSwipe(-1);
      _horizDragAccum = 0;
    }
  }

  void _onHeroHorizontalDragEnd(DragEndDetails _) {
    _horizDragAccum = 0;
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
      setState(() => _browserExpanded = true);
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

    final bool browserCollapsed =
        _browserPresentation == BrowserPresentation.swipeUp &&
            !_browserExpanded;
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
              return AnimatedBuilder(
                animation: _immersiveT,
                builder: (context, _) {
                  final t = _immersiveT.value;
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
                  // When the swipe-up browser is collapsed, the hero
                  // grows down to claim the freed browser slot — only a
                  // thin band at the bottom of that slot stays reserved
                  // for the "↑ swipe to browse" hint. baseHeroH is the
                  // non-immersive height; the immersive interpolation
                  // below still lifts it to availableH at t=1.
                  final double baseHeroH = browserCollapsed
                      ? (availableH -
                          browserBottom -
                          _swipeHintZoneHeight -
                          (isTransportTop ? _transportHeight : 0.0))
                      : heroHeight;
                  // Hero height interpolates from `baseHeroH` (non-
                  // immersive) to the full available height (immersive).
                  // Everything else hangs off the bottom edge so the
                  // hero growth never collides with their fixed slot
                  // (B-003: no layout-time overflow mid-transition).
                  final heroH = baseHeroH + (availableH - baseHeroH) * t;
                  final browserTop =
                      heroH + (isTransportTop ? _transportHeight : 0.0);
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
                      // Browser fills the band between the hero (or the
                      // top-anchored transport) and the crumb (or the
                      // bottom-anchored transport). When the swipe-up
                      // presentation is collapsed the browser is hidden
                      // and a hint zone takes its place.
                      if (showChildren && !browserCollapsed)
                        Positioned(
                          top: browserTop,
                          left: 0,
                          right: 0,
                          bottom: browserBottom,
                          child: ClipRect(
                            clipBehavior: Clip.hardEdge,
                            child: VoidBrowser(
                              controller: _libraryController,
                              searchController: _searchController,
                            ),
                          ),
                        ),
                      // Swipe-up hint band — a thin strip at the bottom
                      // of the freed browser slot. The expanded hero sits
                      // directly above it. Tap / upward drag expands the
                      // browser into view.
                      if (showChildren && browserCollapsed)
                        Positioned(
                          left: 0,
                          right: 0,
                          height: _swipeHintZoneHeight,
                          bottom: browserBottom,
                          child: _buildSwipeUpHint(palette, typography),
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

  /// Android back: collapse the swipe-up browser, then exit search, then
  /// walk one folder up the library tree. Only when all three are
  /// exhausted does PopScope let the pop through and the OS leave the app.
  void _onPopInvoked(bool didPop, Object? _) {
    if (didPop) return;
    if (_browserExpanded &&
        _browserPresentation == BrowserPresentation.swipeUp) {
      setState(() => _browserExpanded = false);
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
        return const VoidHero();
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
              return _buildSearchCrumb(palette, typography);
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
            return MidEllipsis(
              text: path == null || path.isEmpty ? '~' : path,
              style: crumbStyle,
            );
          },
        ),
      ),
    );
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
            child: GestureDetector(
              key: const ValueKey('void-search-close'),
              behavior: HitTestBehavior.opaque,
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
        child: GestureDetector(
          key: const ValueKey('void-settings-button'),
          behavior: HitTestBehavior.opaque,
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
          setState(() => _browserExpanded = true);
          _swipeUpAccum = 0;
        }
      },
      onVerticalDragEnd: (_) => _swipeUpAccum = 0,
      onTap: () => setState(() => _browserExpanded = true),
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
