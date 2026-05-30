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
  // (mutually exclusive, so no conflict).
  final ScrollController _scrollController = ScrollController();

  // B-015: GlobalKey per file row, indexed by track path; kept alive across
  // rebuilds so Scrollable.ensureVisible has a context for the crumb-jump.
  final Map<String, GlobalKey> _fileRowKeys = <String, GlobalKey>{};

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
    _scrollController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
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
    BuildContext? rowContext = _fileRowKeys[path]?.currentContext;
    for (int i = 0; i < 30 && rowContext == null; i++) {
      if (!mounted) return;
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!completer.isCompleted) completer.complete();
      });
      // Ensure the binding has a frame to schedule the callback against.
      WidgetsBinding.instance.scheduleFrame();
      await completer.future;
      if (!mounted) return;
      rowContext = _fileRowKeys[path]?.currentContext;
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
    if (!_scrollController.hasClients) return;
    final hasUp = _controller.currentPath != null ? 1 : 0;
    final childIndex = hasUp + (tracks.length - 1 - index);
    final viewport = _scrollController.position.viewportDimension;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final minScroll = _scrollController.position.minScrollExtent;
    // Per-row pixel cost: prefer measuring a mounted row (accounts for padding +
    // dividers + theme), else AppGeometry.rowHeight.
    final geometry = Theme.of(context).extension<AppGeometry>()!;
    double rowHeight = geometry.rowHeight;
    for (final entry in _fileRowKeys.values) {
      final ctx = entry.currentContext;
      if (ctx == null) continue;
      // Our own GlobalKey context; outer mounted guards cover the lifecycle.
      // ignore: use_build_context_synchronously
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        rowHeight = box.size.height;
        break;
      }
    }
    // Centre the row: subtract half the viewport so it lands near the middle.
    final rawOffset =
        childIndex * rowHeight - (viewport / 2) + (rowHeight / 2);
    final clamped = rawOffset.clamp(minScroll, maxScroll);
    await _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  GlobalKey _keyForTrack(String path) =>
      _fileRowKeys.putIfAbsent(path, GlobalKey.new);

  void _kickOffInit() {
    if (_initStarted) return;
    _initStarted = true;
    // When the parent supplies the controller it owns init (sequencing restore
    // before paint); skip here to avoid racing two concurrent init() calls.
    if (!_ownsController) return;
    _controller.init();
  }

  void _onSearchChanged() {
    final term = widget.searchController?.text.trim() ?? '';
    if (term == _searchTerm) return;
    setState(() {
      _searchTerm = term;
    });
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
    final List<AudioTrack> haystack;
    if (_controller.isAndroid) {
      // Display the on-disk filename (sans extension), matching browser/hero.
      haystack = _controller.androidSongs
          .map((s) => AudioTrack(
                path: s.path,
                title: p.basenameWithoutExtension(s.path),
              ))
          .toList(growable: false);
    } else {
      haystack = await _controller.tracksForCurrentPath();
    }
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
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final geometry = Theme.of(context).extension<AppGeometry>()!;

    _kickOffInit();

    final listBody = Consumer<LibraryController>(
      builder: (context, controller, _) {
        final isPermissionGate = controller.isAndroid && !controller.hasPermission;

        if (isPermissionGate) {
          return _buildPermissionGate(controller, palette, typography);
        }
        // Rebuild when the smart-folders toggle flips so labels swap within a frame.
        return ValueListenableBuilder<bool>(
          valueListenable: SettingsService().smartFoldersPresentationNotifier,
          builder: (_, _, _) =>
              _buildList(controller, palette, typography, geometry),
        );
      },
    );

    // B-032: when dismissable, stack a drag handle + close-gesture header above
    // the list; the gesture wraps only the header so list drags keep scrolling.
    final Widget body = widget.isDismissable
        ? Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _DragHandleAndCloseRegion(
                palette: palette,
                onDragDownClose: widget.onDragDownClose,
              ),
              Expanded(child: listBody),
            ],
          )
        : listBody;

    if (_ownsController) {
      return ChangeNotifierProvider<LibraryController>.value(
        value: _controller,
        child: body,
      );
    }
    return body;
  }

  Widget _buildPermissionGate(
    LibraryController controller,
    AppPalette palette,
    AppTypography typography,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'permissions required',
              style: _mono(typography, palette.fgPrimary, typography.rowSize),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            PressFeedback(
              onTap: controller.requestPermission,
              child: Text(
                'tap to grant',
                style:
                    _mono(typography, palette.fgSecondary, typography.rowSize),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    LibraryController controller,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    if (_searchTerm.isNotEmpty) {
      return _buildSearchResults(palette, typography, geometry);
    }

    final List<Widget> rows = <Widget>[];

    // Folders, then files, then the up row anchored at the list bottom (just
    // above the crumb) so it stays within thumb reach.
    for (final folder in controller.folders) {
      // Folder row: '>' glyph, tap to open, long-press recursive shuffle (≈).
      rows.add(_row(
        key: ValueKey('void-folder:${folder.path}'),
        label: folder.name,
        glyph: '>',
        palette: palette,
        typography: typography,
        geometry: geometry,
        isPlaying: false,
        onTap: () => controller.loadFolder(folder.path),
        onLongPress: () => _playFolderRecursiveShuffled(folder.path),
        previewGlyph: '≈',
      ));
    }
    for (final track in controller.tracks) {
      rows.add(_fileRow(track, controller, palette, typography, geometry));
    }
    if (controller.currentPath != null) {
      // Up row, anchored at the bottom of the reversed list.
      rows.add(_row(
        key: const ValueKey('void-up'),
        label: '..',
        glyph: '<',
        palette: palette,
        typography: typography,
        geometry: geometry,
        isPlaying: false,
        onTap: () => controller.navigateUp(),
      ));
    }

    // Roots (top-level when no path): Android smart roots or filesystem roots.
    if (controller.currentPath == null) {
      if (controller.isAndroid) {
        final friendly =
            SettingsService().smartFoldersPresentationNotifier.value;
        for (final section in controller.androidSmartRootSections) {
          final isFallback = section.entries.length == 1 &&
              section.entries.single == section.deviceRoot;
          for (final path in section.entries) {
            rows.add(_smartRootRow(
              path,
              controller,
              palette,
              typography,
              geometry,
              friendly: friendly,
              isDeviceRootFallback: isFallback,
            ));
          }
        }
      } else {
        final roots = LibraryService().rootsNotifier.value;
        for (final root in roots.keys) {
          // Filesystem root row: keyed by full path, labelled by basename.
          rows.add(_row(
            key: ValueKey('void-root:$root'),
            label: p.basename(root),
            glyph: '>',
            palette: palette,
            typography: typography,
            geometry: geometry,
            isPlaying: false,
            onTap: () => controller.loadFolder(root),
          ));
        }
      }
    }

    if (rows.isEmpty) {
      return _empty('empty', palette, typography);
    }

    // Bottom-anchored: reverse so the first DOM child sits at the visual bottom,
    // and reverse the children so on-screen order matches reading order. B-006:
    // cacheExtent 0 + hardEdge clip stop the reverse-axis cache pre-painting rows
    // above the viewport that would ghost into the hero area.
    return ListView(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
      clipBehavior: Clip.hardEdge,
      children: rows.reversed.toList(growable: false),
    );
  }

  Widget _buildSearchResults(
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    if (_searchResults.isEmpty) {
      return _empty('no matches', palette, typography);
    }
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
      clipBehavior: Clip.hardEdge,
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final reversedIndex = _searchResults.length - 1 - index;
        final track = _searchResults[reversedIndex];
        return _searchResultRow(track, palette, typography, geometry);
      },
    );
  }

  Widget _empty(String text, AppPalette palette, AppTypography typography) {
    return Center(
      child: Text(
        text,
        style: _mono(typography, palette.fgTertiary, typography.rowSize),
      ),
    );
  }

  Widget _fileRow(
    AudioTrack track,
    LibraryController controller,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    final player = context.watch<AudioPlayerProvider>();
    final isPlaying = player.songInfo?.track.path == track.path;
    final row = _row(
      key: ValueKey('void-file:${track.path}'),
      label: track.title,
      glyph: '.',
      palette: palette,
      typography: typography,
      geometry: geometry,
      isPlaying: isPlaying,
      onTap: () => _playFileFromFolder(track, controller),
      onLongPress: () => _playOneShot(track),
      previewGlyph: '↩', // ↩ — one-shot return marker
    );
    // B-015: per-track GlobalKey via KeyedSubtree gives Scrollable.ensureVisible
    // a stable target; the inner row's ValueKey still drives QA taps + identity.
    return KeyedSubtree(
      key: _keyForTrack(track.path),
      child: row,
    );
  }

  Widget _smartRootRow(
    String path,
    LibraryController controller,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry, {
    required bool friendly,
    required bool isDeviceRootFallback,
  }) {
    final String label;
    final String? subLabel;
    if (!friendly) {
      label = path;
      subLabel = null;
    } else if (isDeviceRootFallback) {
      label = fallbackDeviceLabel(path);
      subLabel = path;
    } else {
      final l = labelForPath(path);
      label = l.display;
      subLabel = l.subtitle;
    }
    return _row(
      key: ValueKey('void-smart:$path'),
      label: label,
      subLabel: subLabel,
      glyph: '>',
      palette: palette,
      typography: typography,
      geometry: geometry,
      isPlaying: false,
      onTap: () => controller.loadFolder(path),
    );
  }

  /// Search title: plain mid-ellipsis when unmatched, else a rich span with the
  /// match in fgPrimary. B-019: the highlight branch uses tail-ellipsis.
  Widget _searchTitleLabel(String title, String term, TextStyle titleStyle,
      AppPalette palette) {
    final matchIdx = title.toLowerCase().indexOf(term);
    if (matchIdx < 0) {
      return MidEllipsis(text: title, style: titleStyle);
    }
    return Text.rich(
      TextSpan(
        style: titleStyle,
        children: <TextSpan>[
          TextSpan(text: title.substring(0, matchIdx)),
          TextSpan(
            text: title.substring(matchIdx, matchIdx + term.length),
            style: TextStyle(color: palette.fgPrimary),
          ),
          TextSpan(text: title.substring(matchIdx + term.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _searchResultRow(
    AudioTrack track,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    final parent = p.basename(p.dirname(track.path));
    final titleStyle =
        _mono(typography, palette.fgSecondary, typography.rowSize);
    final labelWidget = _searchTitleLabel(
        track.title, _searchTerm.toLowerCase(), titleStyle, palette);

    // B-014: tapping installs the result list as a sub-queue starting at the
    // tapped track (located by path); see [_playSearchResult]. Shares the row
    // scaffold with [_row] via [titleWidget] — only the title span (search
    // highlight) and the trailing parent-folder hint differ.
    return _row(
      key: ValueKey('void-search:${track.path}'),
      label: track.title,
      titleWidget: labelWidget,
      glyph: '.',
      palette: palette,
      typography: typography,
      geometry: geometry,
      isPlaying: false,
      onTap: () => _playSearchResult(track),
      trailing: parent.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '— $parent',
                style:
                    _mono(typography, palette.fgTertiary, typography.hintSize),
              ),
            ),
    );
  }

  /// Mono text style helper — every row glyph/label shares the same family.
  TextStyle _mono(AppTypography typography, Color color, double size) =>
      TextStyle(color: color, fontFamily: typography.monoFamily, fontSize: size);

  Widget _row({
    required Key key,
    required String label,
    required String glyph,
    required AppPalette palette,
    required AppTypography typography,
    required AppGeometry geometry,
    required bool isPlaying,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    String? previewGlyph,
    String? subLabel,
    // When supplied, used verbatim as the title (e.g. the search-highlight
    // span); otherwise the title is built from [label] exactly as before.
    Widget? titleWidget,
    // Optional trailing widget after the title (e.g. the search parent hint).
    Widget? trailing,
  }) {
    final Color bg = isPlaying ? palette.inverted : Colors.transparent;
    final Color fg = isPlaying ? palette.background : palette.fgPrimary;
    final Color glyphColor = isPlaying ? palette.background : palette.fgTertiary;

    final TextStyle labelStyle = _mono(typography, fg, typography.rowSize);
    final TextStyle subLabelStyle =
        _mono(typography, palette.fgTertiary, typography.crumbSize);
    final Widget labelColumn = titleWidget ??
        (subLabel == null
            ? MidEllipsis(text: label, style: labelStyle)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MidEllipsis(text: label, style: labelStyle),
                  MidEllipsis(text: subLabel, style: subLabelStyle),
                ],
              ));

    return _VoidRow(
      rowKey: key,
      onTap: onTap,
      onLongPress: onLongPress,
      previewGlyph: previewGlyph,
      palette: palette,
      typography: typography,
      geometry: geometry,
      child: Container(
        constraints: BoxConstraints(minHeight: geometry.rowHeight),
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Text(
                glyph,
                style: _mono(typography, glyphColor, typography.rowSize),
              ),
            ),
            Expanded(child: labelColumn),
            ?trailing,
          ],
        ),
      ),
    );
  }

  void _playFileFromFolder(AudioTrack track, LibraryController controller) {
    final player = context.read<AudioPlayerProvider>();
    final tracks = controller.tracks;
    final index = tracks.indexWhere((t) => t.path == track.path);
    final startIndex = index < 0 ? 0 : index;
    player.setQueue(tracks, startIndex: startIndex);
  }

  void _playOneShot(AudioTrack track) {
    final player = context.read<AudioPlayerProvider>();
    player.playOneShot(track);
  }

  /// B-014: install the visible result list as a search-session sub-queue with
  /// the tapped track active; the prior queue is restored on search dismiss.
  void _playSearchResult(AudioTrack track) {
    final player = context.read<AudioPlayerProvider>();
    final results = _searchResults;
    if (results.isEmpty) return;
    final idx = results.indexWhere((t) => t.path == track.path);
    final tappedIndex = idx < 0 ? 0 : idx;
    player.enterSearchSession(results, tappedIndex);
  }

  Future<void> _playFolderRecursiveShuffled(String path) async {
    try {
      final player = context.read<AudioPlayerProvider>();
      // Android loads via tracksForCurrentPath after loadFolder; else scanFolder.
      List<AudioTrack> tracks;
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
        tag: 'VoidBrowser',
        message: 'Recursive shuffle failed for $path: $e',
      );
    }
  }
}

/// B-032: header band atop the open swipe-up browser — drag-handle pill + a
/// dual-threshold drag-down-to-close gesture (B-027 pattern: fires on distance
/// [_dragDistanceThreshold] OR velocity [_dragVelocityThreshold], `_fired` latch
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
  static const double _dragDistanceThreshold = 60.0;
  static const double _dragVelocityThreshold = 300.0;

  double _accum = 0;
  bool _fired = false;

  void _onUpdate(DragUpdateDetails d) {
    if (_fired) return;
    _accum += d.primaryDelta ?? 0;
    // Positive y delta = downward = close.
    if (_accum > _dragDistanceThreshold) {
      _fired = true;
      _accum = 0;
      widget.onDragDownClose?.call();
    }
  }

  void _onEnd(DragEndDetails d) {
    if (!_fired) {
      final v = d.primaryVelocity ?? 0;
      // Positive velocity = downward fling.
      if (v > _dragVelocityThreshold) {
        _fired = true;
        widget.onDragDownClose?.call();
      }
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
        padding: const EdgeInsets.only(top: 10, bottom: 10),
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
    return PressFeedback(
      key: widget.rowKey,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onLongPressStart: widget.onLongPress == null
          ? null
          : (_) => setState(() => _showPreview = true),
      onLongPressEnd: widget.onLongPress == null
          ? null
          : (_) => setState(() => _showPreview = false),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: widget.palette.divider,
              width: widget.geometry.dividerThickness,
            ),
          ),
        ),
        child: Stack(
          children: [
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
          ],
        ),
      ),
    );
  }
}
