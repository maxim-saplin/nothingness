import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../controllers/library_controller.dart';
import '../models/audio_track.dart';
import '../providers/audio_player_provider.dart';
import '../services/library_browser.dart';
import '../services/library_service.dart';
import '../services/logging_service.dart';
import '../services/settings_service.dart';
import '../services/smart_root_labels.dart';
import '../theme/app_geometry.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import 'mid_ellipsis.dart';
import 'press_feedback.dart';

/// A bottom-anchored file-tree browser used by [VoidScreen].
///
/// Mirrors the v6_monk prototype's `#list` zone — full-width rows, thin 1px
/// dividers, bottom-anchored, no chrome. Tap a file to set the current folder
/// as the queue, long-press a file to play it as a one-shot, long-press a
/// folder to recursively shuffle into the queue.
///
/// Search is *not* a visible widget here. The parent owns a [TextEditingController]
/// and toggles search mode (typically by long-pressing the crumb in [VoidScreen]).
/// We listen to that controller and swap the tree for search results when its
/// text is non-empty.
class VoidBrowser extends StatefulWidget {
  const VoidBrowser({
    super.key,
    this.controller,
    this.searchController,
    this.isDismissable = false,
    this.onDragDownClose,
  });

  /// Optional externally-owned controller. When provided, the parent owns the
  /// lifecycle (used so the crumb in [VoidScreen] can read `currentPath`).
  final LibraryController? controller;

  /// Optional externally-owned search controller. When provided we listen to
  /// its text and render search results when it is non-empty. When null we
  /// only render the tree.
  final TextEditingController? searchController;

  /// B-032: When `true`, the browser renders a drag handle pill at the top
  /// and wraps the non-scrolling header band in a vertical-drag-down close
  /// gesture. Set by the parent ([VoidScreen]) only when the browser is in
  /// swipe-up presentation AND currently expanded — fixed presentation never
  /// flips this on because there's no close affordance to surface.
  final bool isDismissable;

  /// B-032: Callback fired when the user crosses the drag-down threshold on
  /// the non-scrolling header band. The parent collapses the browser. Ignored
  /// (effectively absent) when [isDismissable] is `false`.
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

  // B-015: a single ScrollController feeds both the folder ListView and the
  // search-results ListView. The lists are mutually exclusive (search mode
  // swaps one for the other) so they can share state without conflict.
  final ScrollController _scrollController = ScrollController();

  // B-015: GlobalKey per visible file row, indexed by track path. The
  // browser keeps these alive across rebuilds (and across the swap to
  // search results) so `Scrollable.ensureVisible` always has a context
  // for the now-playing row when the user taps the crumb glyph.
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

  /// B-015 / B-031: scroll the row for [path] into view, centered.
  ///
  /// Returns once the row is visible (or once the fallback animateTo
  /// completes). Skips when the track is not in the current folder's
  /// `tracks` list — that's a weird state we leave alone.
  ///
  /// Frame-pumping: a single `endOfFrame` is not enough for the SliverList
  /// to lazy-build a row that lives far outside the current viewport. We
  /// pump up to 30 frames (~500 ms at 60 fps) waiting for the per-row
  /// `GlobalKey.currentContext` to materialise. If it does, we centre via
  /// `Scrollable.ensureVisible` (alignment 0.5). If it never does — very
  /// long folders, or a target row that lives beyond the cache extent —
  /// we fall back to `ScrollController.animateTo` using
  /// `(totalRows - index - 1) * rowHeight` as the offset (the list is
  /// `reverse: true`, so offset 0 corresponds to the last visual row at
  /// the bottom of the viewport).
  Future<void> scrollToTrack(String path) async {
    if (!mounted) return;
    final tracks = _controller.tracks;
    final index = tracks.indexWhere((t) => t.path == path);
    if (index < 0) {
      // Track not in the current folder — caller is responsible for
      // navigating first; nothing sane to scroll to here.
      return;
    }

    // Wait for the target row to be lazy-built. We schedule a post-frame
    // callback after each frame and check whether the row's GlobalKey has
    // materialised; loop up to ~30 frames (~500 ms at 60 fps). Using
    // `addPostFrameCallback` (rather than `endOfFrame`) keeps the test
    // binding happy: the binding always schedules a frame in response to
    // setState / scroll work, so each callback chain progresses without
    // requiring a separate frame to be ticking.
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
      // The context comes from a per-row GlobalKey we own; the loop above
      // re-checks `mounted` on every iteration and only exits the loop with
      // a non-null `rowContext` if we are still mounted. Safe to use.
      await Scrollable.ensureVisible(
        // ignore: use_build_context_synchronously
        rowContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // Row never built — fall back to ScrollController.animateTo. The
    // browser's children-list ordering is:
    //
    //   children = [upRow?, ...tracks.reversed, ...folders.reversed, ...]
    //
    // With `reverse: true`, scroll offset 0 corresponds to the FIRST
    // child (visually at the bottom of the viewport). The visual children
    // index of `tracks[index]` is therefore:
    //
    //   hasUp + (tracks.length - 1 - index)
    //
    // where hasUp is 1 when the up row is rendered (currentPath != null).
    if (!_scrollController.hasClients) return;
    final hasUp = _controller.currentPath != null ? 1 : 0;
    final childIndex = hasUp + (tracks.length - 1 - index);
    final viewport = _scrollController.position.viewportDimension;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final minScroll = _scrollController.position.minScrollExtent;
    // Estimate the per-row pixel cost. We prefer measuring an existing
    // mounted row (the row's RenderObject already knows its laid-out
    // height) so the estimate accounts for padding + dividers + theme.
    // Falls back to `AppGeometry.rowHeight` when no row is mounted yet.
    final geometry = Theme.of(context).extension<AppGeometry>()!;
    double rowHeight = geometry.rowHeight;
    for (final entry in _fileRowKeys.values) {
      final ctx = entry.currentContext;
      if (ctx == null) continue;
      // Contexts come from our own GlobalKey map; the outer `mounted`
      // guards above cover the lifecycle. Safe to read across awaits.
      // ignore: use_build_context_synchronously
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        rowHeight = box.size.height;
        break;
      }
    }
    // Centre the row in the viewport: subtract half the viewport so the
    // row lands near the middle rather than against an edge.
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
    // When the parent supplies the controller it also owns the init
    // lifecycle (so it can sequence work like restoring the last
    // browsed path before the tree paints). Skip the kick-off here to
    // avoid two concurrent init() calls racing against each other.
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
    // B-009: search scope was previously limited to currentPath, so a query
    // typed from a sub-folder ("Indie/") couldn't find tracks living in
    // sibling folders. Search now spans the whole library: the full
    // Android MediaStore song cache on Android, or the currently-loaded
    // tracks on other platforms (macOS uses filesystem traversal lazily).
    final lower = term.toLowerCase();
    final List<AudioTrack> haystack;
    if (_controller.isAndroid) {
      // Display the on-disk filename (sans audio extension), matching the
      // browser/hero. MediaStore's ID3-derived title is irrelevant for
      // search rows — the user expects to recognise the filename they
      // typed against.
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
        // Rebuild whenever the smart-folders presentation toggle flips so
        // labels swap to/from raw paths within a frame.
        return ValueListenableBuilder<bool>(
          valueListenable: SettingsService().smartFoldersPresentationNotifier,
          builder: (_, _, _) =>
              _buildList(controller, palette, typography, geometry),
        );
      },
    );

    // B-032: When the browser is presented as a dismissable sheet (swipe-up
    // mode, currently expanded), stack a drag handle + close-gesture region
    // on top of the scrollable list. The gesture region wraps ONLY the
    // header band so vertical drags inside the list keep scrolling instead
    // of accidentally collapsing the browser.
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
              style: TextStyle(
                color: palette.fgPrimary,
                fontFamily: typography.monoFamily,
                fontSize: typography.rowSize,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            PressFeedback(
              onTap: controller.requestPermission,
              child: Text(
                'tap to grant',
                style: TextStyle(
                  color: palette.fgSecondary,
                  fontFamily: typography.monoFamily,
                  fontSize: typography.rowSize,
                ),
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

    // Folders, then files, then the up row anchored at the very bottom of
    // the list (just above the crumb) so it sits within reach of the
    // user's thumb instead of being hidden at the top of a long folder.
    for (final folder in controller.folders) {
      rows.add(_folderRow(folder, controller, palette, typography, geometry));
    }
    for (final track in controller.tracks) {
      rows.add(_fileRow(track, controller, palette, typography, geometry));
    }
    if (controller.currentPath != null) {
      rows.add(_upRow(controller, palette, typography, geometry));
    }

    // Android smart roots (top-level when no path).
    if (controller.currentPath == null) {
      if (controller.isAndroid) {
        final friendly = SettingsService()
            .smartFoldersPresentationNotifier
            .value;
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
          rows.add(_macRootRow(root, controller, palette, typography, geometry));
        }
      }
    }

    if (rows.isEmpty) {
      return _empty('empty', palette, typography);
    }

    // Bottom-anchored list: reverse so the first DOM child sits at the visual
    // bottom (adjacent to the crumb / search).  We reverse the children list
    // so the on-screen order matches the natural reading order.
    //
    // `cacheExtent: 0` and `clipBehavior: Clip.hardEdge` are belt-and-braces
    // for B-006: with a reverse-axis viewport the default 250 px cache
    // pre-paints rows ABOVE the viewport, which (combined with the parent
    // Stack/Opacity composition) would otherwise ghost-render those rows
    // into the hero area sitting above the browser.
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
        style: TextStyle(
          color: palette.fgTertiary,
          fontFamily: typography.monoFamily,
          fontSize: typography.rowSize,
        ),
      ),
    );
  }

  Widget _upRow(
    LibraryController controller,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    return _row(
      key: const ValueKey('void-up'),
      label: '..',
      glyph: '<',
      palette: palette,
      typography: typography,
      geometry: geometry,
      isPlaying: false,
      onTap: () => controller.navigateUp(),
    );
  }

  Widget _folderRow(
    LibraryFolder folder,
    LibraryController controller,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    return _row(
      key: ValueKey('void-folder:${folder.path}'),
      label: folder.name,
      glyph: '>',
      palette: palette,
      typography: typography,
      geometry: geometry,
      isPlaying: false,
      onTap: () => controller.loadFolder(folder.path),
      onLongPress: () => _playFolderRecursiveShuffled(folder.path),
      previewGlyph: '≈', // ≈ — recursive shuffle preview marker
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
    // B-015: wrap each file row in a KeyedSubtree carrying a per-track
    // GlobalKey so `Scrollable.ensureVisible` has a stable BuildContext
    // target when the crumb-jump tap asks us to centre the now-playing row.
    // The ValueKey on the inner row still drives QA taps and identity.
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

  Widget _macRootRow(
    String path,
    LibraryController controller,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    return _row(
      key: ValueKey('void-root:$path'),
      label: p.basename(path),
      glyph: '>',
      palette: palette,
      typography: typography,
      geometry: geometry,
      isPlaying: false,
      onTap: () => controller.loadFolder(path),
    );
  }

  Widget _searchResultRow(
    AudioTrack track,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    final parent = p.basename(p.dirname(track.path));
    final term = _searchTerm.toLowerCase();
    final title = track.title;
    final lowerTitle = title.toLowerCase();
    final matchIdx = lowerTitle.indexOf(term);

    final titleStyle = TextStyle(
      color: palette.fgSecondary,
      fontFamily: typography.monoFamily,
      fontSize: typography.rowSize,
    );
    Widget labelWidget;
    if (matchIdx < 0) {
      labelWidget = MidEllipsis(text: title, style: titleStyle);
    } else {
      // Highlight path: a rich span with the match in fgPrimary. We can't
      // run the head-ellipsis measurement across multi-style spans without
      // significant complexity, so we keep this branch on the default
      // tail-ellipsis. B-019 trade-off — the highlighted match remains
      // visible from the start.
      final before = title.substring(0, matchIdx);
      final match = title.substring(matchIdx, matchIdx + term.length);
      final after = title.substring(matchIdx + term.length);
      labelWidget = Text.rich(
        TextSpan(
          style: titleStyle,
          children: <TextSpan>[
            TextSpan(text: before),
            TextSpan(
              text: match,
              style: TextStyle(color: palette.fgPrimary),
            ),
            TextSpan(text: after),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // B-014: tapping a search result installs the entire result list as a
    // sub-queue and starts at the tapped track. Closing search restores the
    // prior queue. We need the *index inside the result list* — locate the
    // tapped track by path so re-orderings don't get out of sync.
    return PressFeedback(
      key: ValueKey('void-search:${track.path}'),
      onTap: () => _playSearchResult(track),
      child: Container(
        constraints: BoxConstraints(minHeight: geometry.rowHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: palette.divider,
              width: geometry.dividerThickness,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Text(
                '.',
                style: TextStyle(
                  color: palette.fgTertiary,
                  fontFamily: typography.monoFamily,
                  fontSize: typography.rowSize,
                ),
              ),
            ),
            Expanded(child: labelWidget),
            if (parent.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  '— $parent',
                  style: TextStyle(
                    color: palette.fgTertiary,
                    fontFamily: typography.monoFamily,
                    fontSize: typography.hintSize,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
  }) {
    final Color bg = isPlaying ? palette.inverted : Colors.transparent;
    final Color fg = isPlaying ? palette.background : palette.fgPrimary;
    final Color glyphColor = isPlaying ? palette.background : palette.fgTertiary;

    final TextStyle labelStyle = TextStyle(
      color: fg,
      fontFamily: typography.monoFamily,
      fontSize: typography.rowSize,
    );
    final TextStyle subLabelStyle = TextStyle(
      color: palette.fgTertiary,
      fontFamily: typography.monoFamily,
      fontSize: typography.crumbSize,
    );
    final Widget labelColumn = subLabel == null
        ? MidEllipsis(text: label, style: labelStyle)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MidEllipsis(text: label, style: labelStyle),
              MidEllipsis(text: subLabel, style: subLabelStyle),
            ],
          );

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
                style: TextStyle(
                  color: glyphColor,
                  fontFamily: typography.monoFamily,
                  fontSize: typography.rowSize,
                ),
              ),
            ),
            Expanded(child: labelColumn),
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

  /// B-014: tapping a search result installs the visible result list as a
  /// search-session sub-queue with the tapped track active. The prior queue
  /// is preserved by [PlaybackController] and restored when search is
  /// dismissed by [VoidScreen]. Routed via [AudioPlayerProvider] so the
  /// Android handler can dispatch the same custom action.
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
      // Use the controller's recursive-flat call when available; otherwise
      // fall back to scanFolder (filesystem). Android smart roots already
      // load via tracksForCurrentPath after loadFolder.
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

/// B-032: header band painted at the top of the open swipe-up browser. Renders
/// the drag-handle pill and owns the vertical-drag-down-to-close gesture.
///
/// The gesture uses the same dual-threshold pattern as B-027's horizontal
/// hero swipe: fires the close callback when either the accumulated downward
/// distance crosses [_dragDistanceThreshold], or the end-of-drag velocity
/// exceeds [_dragVelocityThreshold]. A `_fired` latch on the State prevents
/// the velocity escape from double-firing on top of a distance trip.
///
/// Only the header band hosts the gesture — the scrollable list below it
/// keeps its own ScrollController-driven vertical scrolling untouched.
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
  // B-032 / B-027: matched thresholds for the dual-threshold close gesture.
  // 60 dp distance OR > 300 dp/s end-velocity, whichever fires first.
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
    // Full-width hit region so the user can start the drag-down close
    // anywhere along the header band, not just on the 32-px pill itself.
    return GestureDetector(
      key: const ValueKey('void-browser-close-drag-region'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onUpdate,
      onVerticalDragEnd: _onEnd,
      child: Container(
        key: const ValueKey('void-browser-drag-handle'),
        width: double.infinity,
        // Margin sits the pill in a clear 8-px band above the list.
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        alignment: Alignment.center,
        child: Container(
          key: const ValueKey('void-browser-drag-handle-pill'),
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: widget.palette.fgTertiary,
            borderRadius: BorderRadius.circular(2),
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
