import 'package:flutter/material.dart';
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
  });

  /// Optional externally-owned controller. When provided, the parent owns the
  /// lifecycle (used so the crumb in [VoidScreen] can read `currentPath`).
  final LibraryController? controller;

  /// Optional externally-owned search controller. When provided we listen to
  /// its text and render search results when it is non-empty. When null we
  /// only render the tree.
  final TextEditingController? searchController;

  @override
  State<VoidBrowser> createState() => _VoidBrowserState();
}

class _VoidBrowserState extends State<VoidBrowser> {
  late final LibraryController _controller;
  late final bool _ownsController;
  bool _initStarted = false;
  String _searchTerm = '';
  List<AudioTrack> _searchResults = const <AudioTrack>[];

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
  void didUpdateWidget(covariant VoidBrowser old) {
    super.didUpdateWidget(old);
    if (old.searchController != widget.searchController) {
      old.searchController?.removeListener(_onSearchChanged);
      widget.searchController?.addListener(_onSearchChanged);
    }
  }

  @override
  void dispose() {
    widget.searchController?.removeListener(_onSearchChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

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
      haystack = _controller.androidSongs
          .map((s) => AudioTrack(path: s.path, title: s.title))
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

    final body = Consumer<LibraryController>(
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
            GestureDetector(
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
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      cacheExtent: 0,
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
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      cacheExtent: 0,
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
    return _row(
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

    Widget labelWidget;
    if (matchIdx < 0) {
      labelWidget = Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.fgSecondary,
          fontFamily: typography.monoFamily,
          fontSize: typography.rowSize,
        ),
      );
    } else {
      final before = title.substring(0, matchIdx);
      final match = title.substring(matchIdx, matchIdx + term.length);
      final after = title.substring(matchIdx + term.length);
      labelWidget = Text.rich(
        TextSpan(
          style: TextStyle(
            color: palette.fgSecondary,
            fontFamily: typography.monoFamily,
            fontSize: typography.rowSize,
          ),
          children: <TextSpan>[
            TextSpan(text: before),
            TextSpan(
              text: match,
              style: TextStyle(color: palette.fgPrimary),
            ),
            TextSpan(text: after),
          ],
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return GestureDetector(
      key: ValueKey('void-search:${track.path}'),
      onTap: () => _playOneShot(track),
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

    final Widget labelColumn = subLabel == null
        ? Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontFamily: typography.monoFamily,
              fontSize: typography.rowSize,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontFamily: typography.monoFamily,
                  fontSize: typography.rowSize,
                ),
              ),
              Text(
                subLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.fgTertiary,
                  fontFamily: typography.monoFamily,
                  fontSize: typography.crumbSize,
                ),
              ),
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
    return GestureDetector(
      key: widget.rowKey,
      onTap: widget.onTap,
      onLongPressStart: widget.onLongPress == null
          ? null
          : (_) => setState(() => _showPreview = true),
      onLongPressEnd: widget.onLongPress == null
          ? null
          : (_) => setState(() => _showPreview = false),
      onLongPress: widget.onLongPress,
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
