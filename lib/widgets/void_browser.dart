import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../controllers/library_controller.dart';
import '../models/audio_track.dart';
import '../providers/audio_player_provider.dart';
import '../services/android_smart_roots.dart';
import '../services/library_browser.dart';
import '../services/library_service.dart';
import '../services/logging_service.dart';
import '../services/settings_service.dart';
import '../theme/app_geometry.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import 'mid_ellipsis.dart';
import 'press_feedback.dart';

/// Bottom-anchored file-tree browser used by [VoidScreen]: full-width rows,
/// thin dividers, no chrome. Tap a file to queue its folder, long-press a file
/// for one-shot, long-press a folder to recursively shuffle. Search is owned by
/// the parent's [TextEditingController]; we swap the tree for results when its
/// text is non-empty.
class VoidBrowser extends StatefulWidget {
  const VoidBrowser({
    super.key,
    this.controller,
    this.searchController,
    this.isDismissable = false,
    this.onDragDownClose,
  });

  /// Externally-owned controller; when provided the parent owns the lifecycle
  /// (so the crumb in [VoidScreen] can read `currentPath`).
  final LibraryController? controller;

  /// Externally-owned search controller; when provided we render search results
  /// when its text is non-empty, otherwise only the tree.
  final TextEditingController? searchController;

  /// B-032: when true, render a drag-handle pill and wrap the header band in a
  /// drag-down close gesture. Set by the parent only for an expanded swipe-up
  /// browser; fixed presentation has no close affordance.
  final bool isDismissable;

  /// B-032: fired when the drag-down threshold is crossed on the header band;
  /// the parent collapses the browser. Ignored when [isDismissable] is false.
  final VoidCallback? onDragDownClose;

  @override
  State<VoidBrowser> createState() => VoidBrowserState();
}

class VoidBrowserState extends State<VoidBrowser> {
  late final LibraryController _controller;
  late final bool _ownsController;
  bool _initStarted = false;
  String _searchTerm = '';
  List<AudioTrack> _searchResults = const <AudioTrack>[];

  // B-015: one ScrollController shared by the folder + search-results ListViews
  // (mutually exclusive, so no conflict). The per-track GlobalKeys (KeyedSubtree
  // wrappers) give Scrollable.ensureVisible a stable target across rebuilds.
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        LibraryController(
          libraryBrowser: LibraryBrowser(
            supportedExtensions: AudioPlayerProvider.supportedExtensions,
          ),
          libraryService: LibraryService(),
        );
    widget.searchController?.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant VoidBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController?.removeListener(_onSearchChanged);
      widget.searchController?.addListener(_onSearchChanged);
    }
  }

  @override
  void dispose() {
    widget.searchController?.removeListener(_onSearchChanged);
    _scroll.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// B-015 / B-031: centre the row for [path] in view; skips when the track
  /// isn't in the current folder. A SliverList won't lazy-build a far-offscreen
  /// row in one frame, so we pump up to 30 frames (~500 ms) for its GlobalKey
  /// context, then centre via Scrollable.ensureVisible, falling back to animateTo.
  Future<void> scrollToTrack(String path) async {
    if (!mounted) return;
    final tracks = _controller.tracks;
    final index = tracks.indexWhere((t) => t.path == path);
    if (index < 0) return;

    // addPostFrameCallback (vs endOfFrame) keeps the test binding progressing.
    BuildContext? rowContext = _rowKeys[path]?.currentContext;
    for (var i = 0; i < 30 && rowContext == null; i++) {
      if (!mounted) return;
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
      WidgetsBinding.instance.scheduleFrame(); // give the binding a frame
      await completer.future;
      if (!mounted) return;
      rowContext = _rowKeys[path]?.currentContext;
    }
    if (!mounted) return;

    if (rowContext != null) {
      // Per-row GlobalKey context; the loop re-checks mounted each iteration.
      await Scrollable.ensureVisible(
        // ignore: use_build_context_synchronously
        rowContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // Row never built — fall back to animateTo. With reverse: true, offset 0 is
    // the visual bottom, so child index is hasUp + (tracks.length - 1 - index).
    if (!_scroll.hasClients) return;
    final hasUp = _controller.currentPath != null ? 1 : 0;
    final childIndex = hasUp + (tracks.length - 1 - index);
    final pos = _scroll.position;
    // Per-row pixel cost: prefer a measured mounted row (padding + dividers +
    // theme), else AppGeometry.rowHeight.
    var rowHeight = Theme.of(context).extension<AppGeometry>()!.rowHeight;
    for (final key in _rowKeys.values) {
      // Our own GlobalKey context; outer mounted guards cover the lifecycle.
      // ignore: use_build_context_synchronously
      final box = key.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        rowHeight = box.size.height;
        break;
      }
    }
    // Centre the row: subtract half the viewport so it lands near the middle.
    final target = (childIndex * rowHeight -
            pos.viewportDimension / 2 +
            rowHeight / 2)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    await _scroll.animateTo(target,
        duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
  }

  void _kickOffInit() {
    if (_initStarted) return;
    _initStarted = true;
    // When the parent supplies the controller it owns init (sequencing restore
    // before paint); skip here to avoid racing two concurrent init() calls.
    if (_ownsController) _controller.init();
  }

  void _onSearchChanged() {
    final term = widget.searchController?.text.trim() ?? '';
    if (term == _searchTerm) return;
    setState(() => _searchTerm = term);
    if (term.isNotEmpty) {
      _runSearch(term);
    } else {
      setState(() => _searchResults = const <AudioTrack>[]);
    }
  }

  Future<void> _runSearch(String term) async {
    // B-009: search spans the whole library — Android MediaStore cache on
    // Android, currently-loaded tracks elsewhere.
    final lower = term.toLowerCase();
    final haystack = _controller.isAndroid
        // Display the on-disk filename (sans extension), matching browser/hero.
        ? _controller.androidSongs
            .map((s) => AudioTrack(
                path: s.path, title: p.basenameWithoutExtension(s.path)))
            .toList(growable: false)
        : await _controller.tracksForCurrentPath();
    final matches = haystack
        .where((t) =>
            t.title.toLowerCase().contains(lower) ||
            p.basename(t.path).toLowerCase().contains(lower))
        .toList(growable: false);
    if (!mounted) return;
    setState(() => _searchResults = matches);
  }

  @override
  Widget build(BuildContext context) {
    final theme = _BrowserTheme.of(context);
    _kickOffInit();

    final listBody = Consumer<LibraryController>(
      builder: (context, controller, _) {
        if (controller.isAndroid && !controller.hasPermission) {
          return _permissionGate(controller, theme);
        }
        // Rebuild when the smart-folders toggle flips so labels swap in a frame.
        return ValueListenableBuilder<bool>(
          valueListenable: SettingsService().smartFoldersPresentationNotifier,
          builder: (_, _, _) => _list(controller, theme),
        );
      },
    );

    // B-032: when dismissable, stack a drag handle + close-gesture header above
    // the list; the gesture wraps only the header so list drags keep scrolling.
    final Widget body = widget.isDismissable
        ? Column(children: [
            _DragHandleAndCloseRegion(
              palette: theme.palette,
              onDragDownClose: widget.onDragDownClose,
            ),
            Expanded(child: listBody),
          ])
        : listBody;

    return _ownsController
        ? ChangeNotifierProvider<LibraryController>.value(
            value: _controller, child: body)
        : body;
  }

  Widget _permissionGate(LibraryController controller, _BrowserTheme t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('permissions required',
                style: t.mono(t.palette.fgPrimary, t.type.rowSize),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            PressFeedback(
              onTap: controller.requestPermission,
              child: Text('tap to grant',
                  style: t.mono(t.palette.fgSecondary, t.type.rowSize)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(LibraryController controller, _BrowserTheme t) {
    if (_searchTerm.isNotEmpty) return _searchList(t);

    // Folders, then files, then the up row anchored at the list bottom (just
    // above the crumb) so it stays within thumb reach.
    final rows = <Widget>[
      for (final folder in controller.folders)
        // Folder row: '>' glyph, tap to open, long-press recursive shuffle (≈).
        _row(t,
            key: ValueKey('void-folder:${folder.path}'),
            label: folder.name,
            glyph: '>',
            onTap: () => controller.loadFolder(folder.path),
            onLongPress: () => _playFolderRecursiveShuffled(folder.path),
            previewGlyph: '≈'),
      for (final track in controller.tracks) _fileRow(track, controller, t),
      // Up row, anchored at the bottom of the reversed list.
      if (controller.currentPath != null)
        _row(t,
            key: const ValueKey('void-up'),
            label: '..',
            glyph: '<',
            onTap: controller.navigateUp),
      // Roots (top-level when no path): Android smart roots or filesystem roots.
      if (controller.currentPath == null) ..._rootRows(controller, t),
    ];

    if (rows.isEmpty) return _empty('empty', t);

    // Bottom-anchored: reverse so the first DOM child sits at the visual bottom,
    // and reverse the children so on-screen order matches reading order. B-006:
    // cacheExtent 0 + hardEdge clip stop the reverse-axis cache pre-painting rows
    // above the viewport that would ghost into the hero area.
    return ListView(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
      clipBehavior: Clip.hardEdge,
      children: rows.reversed.toList(growable: false),
    );
  }

  Iterable<Widget> _rootRows(LibraryController controller, _BrowserTheme t) sync* {
    if (controller.isAndroid) {
      final friendly = SettingsService().smartFoldersPresentationNotifier.value;
      for (final section in controller.androidSmartRootSections) {
        final isFallback = section.entries.length == 1 &&
            section.entries.single == section.deviceRoot;
        for (final path in section.entries) {
          yield _smartRootRow(path, controller, t,
              friendly: friendly, isDeviceRootFallback: isFallback);
        }
      }
    } else {
      for (final root in LibraryService().rootsNotifier.value.keys) {
        // Filesystem root row: keyed by full path, labelled by basename.
        yield _row(t,
            key: ValueKey('void-root:$root'),
            label: p.basename(root),
            glyph: '>',
            onTap: () => controller.loadFolder(root));
      }
    }
  }

  Widget _searchList(_BrowserTheme t) {
    if (_searchResults.isEmpty) return _empty('no matches', t);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
      clipBehavior: Clip.hardEdge,
      itemCount: _searchResults.length,
      itemBuilder: (_, index) =>
          _searchResultRow(_searchResults[_searchResults.length - 1 - index], t),
    );
  }

  Widget _empty(String text, _BrowserTheme t) => Center(
        child: Text(text, style: t.mono(t.palette.fgTertiary, t.type.rowSize)),
      );

  Widget _fileRow(AudioTrack track, LibraryController controller, _BrowserTheme t) {
    final isPlaying =
        context.watch<AudioPlayerProvider>().songInfo?.track.path == track.path;
    // B-015: per-track GlobalKey via KeyedSubtree gives Scrollable.ensureVisible
    // a stable target; the inner row's ValueKey still drives QA taps + identity.
    return KeyedSubtree(
      key: _rowKeys.putIfAbsent(track.path, GlobalKey.new),
      child: _row(t,
          key: ValueKey('void-file:${track.path}'),
          label: track.title,
          glyph: '.',
          isPlaying: isPlaying,
          onTap: () => _playFileFromFolder(track, controller),
          onLongPress: () => _playOneShot(track),
          previewGlyph: '↩'), // ↩ — one-shot return marker
    );
  }

  Widget _smartRootRow(
    String path,
    LibraryController controller,
    _BrowserTheme t, {
    required bool friendly,
    required bool isDeviceRootFallback,
  }) {
    String label;
    String? subLabel;
    if (!friendly) {
      label = path;
    } else if (isDeviceRootFallback) {
      label = fallbackDeviceLabel(path);
      subLabel = path;
    } else {
      final l = labelForPath(path);
      label = l.display;
      subLabel = l.subtitle;
    }
    return _row(t,
        key: ValueKey('void-smart:$path'),
        label: label,
        subLabel: subLabel,
        glyph: '>',
        onTap: () => controller.loadFolder(path));
  }

  /// Search title: plain mid-ellipsis when unmatched, else a rich span with the
  /// match in fgPrimary. B-019: the highlight branch uses tail-ellipsis.
  Widget _searchTitleLabel(
      String title, String term, TextStyle style, AppPalette palette) {
    final i = title.toLowerCase().indexOf(term);
    if (i < 0) return MidEllipsis(text: title, style: style);
    return Text.rich(
      TextSpan(style: style, children: [
        TextSpan(text: title.substring(0, i)),
        TextSpan(
            text: title.substring(i, i + term.length),
            style: TextStyle(color: palette.fgPrimary)),
        TextSpan(text: title.substring(i + term.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _searchResultRow(AudioTrack track, _BrowserTheme t) {
    final parent = p.basename(p.dirname(track.path));
    // B-014: tapping installs the result list as a sub-queue starting at the
    // tapped track (located by path); see [_playSearchResult]. Shares the row
    // scaffold with [_row] via [titleWidget] — only the title span (search
    // highlight) and the trailing parent-folder hint differ.
    return _row(t,
        key: ValueKey('void-search:${track.path}'),
        label: track.title,
        titleWidget: _searchTitleLabel(track.title, _searchTerm.toLowerCase(),
            t.mono(t.palette.fgSecondary, t.type.rowSize), t.palette),
        glyph: '.',
        onTap: () => _playSearchResult(track),
        trailing: parent.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text('— $parent',
                    style: t.mono(t.palette.fgTertiary, t.type.hintSize)),
              ));
  }

  Widget _row(
    _BrowserTheme t, {
    required Key key,
    required String label,
    required String glyph,
    required VoidCallback onTap,
    bool isPlaying = false,
    VoidCallback? onLongPress,
    String? previewGlyph,
    String? subLabel,
    // When supplied, used verbatim as the title (e.g. the search-highlight
    // span); otherwise the title is built from [label].
    Widget? titleWidget,
    // Optional trailing widget after the title (e.g. the search parent hint).
    Widget? trailing,
  }) {
    final palette = t.palette;
    final bg = isPlaying ? palette.inverted : Colors.transparent;
    final fg = isPlaying ? palette.background : palette.fgPrimary;
    final glyphColor = isPlaying ? palette.background : palette.fgTertiary;
    final labelStyle = t.mono(fg, t.type.rowSize);

    final labelColumn = titleWidget ??
        (subLabel == null
            ? MidEllipsis(text: label, style: labelStyle)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MidEllipsis(text: label, style: labelStyle),
                  MidEllipsis(
                      text: subLabel,
                      style: t.mono(palette.fgTertiary, t.type.crumbSize)),
                ],
              ));

    return _VoidRow(
      rowKey: key,
      onTap: onTap,
      onLongPress: onLongPress,
      previewGlyph: previewGlyph,
      palette: palette,
      typography: t.type,
      geometry: t.geometry,
      child: Container(
        constraints: BoxConstraints(minHeight: t.geometry.rowHeight),
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          SizedBox(
              width: 16,
              child: Text(glyph, style: t.mono(glyphColor, t.type.rowSize))),
          Expanded(child: labelColumn),
          ?trailing,
        ]),
      ),
    );
  }

  void _playFileFromFolder(AudioTrack track, LibraryController controller) {
    final tracks = controller.tracks;
    final index = tracks.indexWhere((t) => t.path == track.path);
    context
        .read<AudioPlayerProvider>()
        .setQueue(tracks, startIndex: index < 0 ? 0 : index);
  }

  void _playOneShot(AudioTrack track) =>
      context.read<AudioPlayerProvider>().playOneShot(track);

  /// B-014: install the visible result list as a search-session sub-queue with
  /// the tapped track active; the prior queue is restored on search dismiss.
  void _playSearchResult(AudioTrack track) {
    final results = _searchResults;
    if (results.isEmpty) return;
    final idx = results.indexWhere((t) => t.path == track.path);
    context
        .read<AudioPlayerProvider>()
        .enterSearchSession(results, idx < 0 ? 0 : idx);
  }

  Future<void> _playFolderRecursiveShuffled(String path) async {
    try {
      final player = context.read<AudioPlayerProvider>();
      // Android loads via tracksForCurrentPath after loadFolder; else scanFolder.
      final List<AudioTrack> tracks;
      if (_controller.isAndroid) {
        await _controller.loadFolder(path);
        tracks = await _controller.tracksForCurrentPath();
      } else {
        tracks = await player.scanFolder(path);
      }
      if (tracks.isEmpty) return;
      await player.setQueue(tracks, startIndex: 0, shuffle: true);
    } catch (e) {
      LoggingService().log(
          tag: 'VoidBrowser', message: 'Recursive shuffle failed for $path: $e');
    }
  }
}

/// Resolved theme extensions + the shared mono text-style helper — every row
/// glyph/label uses the same family, so we thread one bundle through builders.
class _BrowserTheme {
  const _BrowserTheme(this.palette, this.type, this.geometry);

  final AppPalette palette;
  final AppTypography type;
  final AppGeometry geometry;

  factory _BrowserTheme.of(BuildContext context) {
    final theme = Theme.of(context);
    return _BrowserTheme(
      theme.extension<AppPalette>()!,
      theme.extension<AppTypography>()!,
      theme.extension<AppGeometry>()!,
    );
  }

  TextStyle mono(Color color, double size) =>
      TextStyle(color: color, fontFamily: type.monoFamily, fontSize: size);
}

/// B-032: header band atop the open swipe-up browser — drag-handle pill + a
/// dual-threshold drag-down-to-close gesture (B-027 pattern: fires on distance
/// [_distanceThreshold] OR velocity [_velocityThreshold], `_fired` latch
/// prevents double-firing). Only the band hosts the gesture; the list scrolls free.
class _DragHandleAndCloseRegion extends StatefulWidget {
  const _DragHandleAndCloseRegion({
    required this.palette,
    required this.onDragDownClose,
  });

  final AppPalette palette;
  final VoidCallback? onDragDownClose;

  @override
  State<_DragHandleAndCloseRegion> createState() =>
      _DragHandleAndCloseRegionState();
}

class _DragHandleAndCloseRegionState extends State<_DragHandleAndCloseRegion> {
  // B-032 / B-027: 60 dp distance OR > 300 dp/s end-velocity, whichever first.
  static const double _distanceThreshold = 60;
  static const double _velocityThreshold = 300;

  double _accum = 0;
  bool _fired = false;

  void _onUpdate(DragUpdateDetails d) {
    if (_fired) return;
    _accum += d.primaryDelta ?? 0; // positive y delta = downward = close
    if (_accum > _distanceThreshold) {
      _fired = true;
      _accum = 0;
      widget.onDragDownClose?.call();
    }
  }

  void _onEnd(DragEndDetails d) {
    // Positive velocity = downward fling.
    if (!_fired && (d.primaryVelocity ?? 0) > _velocityThreshold) {
      widget.onDragDownClose?.call();
    }
    _accum = 0;
    _fired = false;
  }

  @override
  Widget build(BuildContext context) {
    // Full-width hit region so the drag-down close can start anywhere on the band.
    return GestureDetector(
      key: const ValueKey('void-browser-close-drag-region'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onUpdate,
      onVerticalDragEnd: _onEnd,
      child: Container(
        key: const ValueKey('void-browser-drag-handle'),
        width: double.infinity,
        // B-033: 10 px band so the pill reads as separate from the list.
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        child: Container(
          key: const ValueKey('void-browser-drag-handle-pill'),
          // B-033: 40×6 fgSecondary pill (was 32×4 fgTertiary, near-invisible).
          width: 40,
          height: 6,
          decoration: BoxDecoration(
            color: widget.palette.fgSecondary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// One browser row: a divider-underlined [PressFeedback] that overlays a faint
/// [previewGlyph] while a long-press is held (B-030 press feedback).
class _VoidRow extends StatefulWidget {
  const _VoidRow({
    required this.rowKey,
    required this.onTap,
    required this.onLongPress,
    required this.previewGlyph,
    required this.palette,
    required this.typography,
    required this.geometry,
    required this.child,
  });

  final Key rowKey;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? previewGlyph;
  final AppPalette palette;
  final AppTypography typography;
  final AppGeometry geometry;
  final Widget child;

  @override
  State<_VoidRow> createState() => _VoidRowState();
}

class _VoidRowState extends State<_VoidRow> {
  bool _showPreview = false;

  @override
  Widget build(BuildContext context) {
    final hasLongPress = widget.onLongPress != null;
    return PressFeedback(
      key: widget.rowKey,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onLongPressStart:
          hasLongPress ? (_) => setState(() => _showPreview = true) : null,
      onLongPressEnd:
          hasLongPress ? (_) => setState(() => _showPreview = false) : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: widget.palette.divider,
              width: widget.geometry.dividerThickness,
            ),
          ),
        ),
        child: Stack(children: [
          widget.child,
          if (_showPreview && widget.previewGlyph != null)
            Positioned(
              right: 18,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  widget.previewGlyph!,
                  style: TextStyle(
                    color: widget.palette.fgTertiary,
                    fontFamily: widget.typography.monoFamily,
                    fontSize: widget.typography.hintSize,
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
