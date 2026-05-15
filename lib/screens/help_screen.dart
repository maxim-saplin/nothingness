import 'package:flutter/material.dart';

import '../theme/app_geometry.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';

/// Inline cheat-sheet describing every gesture / control available across
/// the Void chrome. Reached from the ABOUT group of [VoidSettingsSheet].
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final geometry = Theme.of(context).extension<AppGeometry>()!;

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(context, palette, typography),
            _group('HERO', palette, typography),
            _entry('tap', 'play / pause the current track',
                palette, typography, geometry),
            _entry('swipe →', 'next track',
                palette, typography, geometry),
            _entry('swipe ←', 'previous track',
                palette, typography, geometry),
            _group('BROWSER', palette, typography),
            _entry('tap folder', 'enter folder',
                palette, typography, geometry),
            _entry('long-press folder', 'recursively shuffle all tracks',
                palette, typography, geometry),
            _entry('tap track', 'replace queue with the folder; play this',
                palette, typography, geometry),
            _entry('long-press track', 'play once, then resume previous queue',
                palette, typography, geometry),
            _entry('< ..', 'go up one folder (bottom of the list)',
                palette, typography, geometry),
            _entry('back button', 'go up one folder; exits at root',
                palette, typography, geometry),
            _group('CRUMB', palette, typography),
            _entry('long-press crumb', 'enter search across the whole library',
                palette, typography, geometry),
            _entry('× in search', 'leave search mode',
                palette, typography, geometry),
            _group('TRANSPORT', palette, typography),
            _entry('icons', 'prev / play-pause / next',
                palette, typography, geometry),
            _entry('hairline above icons', 'tap or drag to seek',
                palette, typography, geometry),
            _entry('hairline at bottom', 'read-only progress',
                palette, typography, geometry),
            _group('CHROME', palette, typography),
            _entry('⋮ top-right', 'open settings',
                palette, typography, geometry),
            _entry('immersive', 'hide chrome — hero fills the screen',
                palette, typography, geometry),
            _entry('transport', 'collapse the prev/play/next strip',
                palette, typography, geometry),
            _entry('screen', 'cycle visualisation (spectrum / polo / dot / void)',
                palette, typography, geometry),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppPalette palette,
    AppTypography typography,
  ) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '<',
                style: TextStyle(
                  color: palette.fgSecondary,
                  fontFamily: typography.monoFamily,
                  fontSize: typography.rowSize,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'help',
            style: TextStyle(
              color: palette.fgPrimary,
              fontFamily: typography.monoFamily,
              fontSize: typography.rowSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(
    String text,
    AppPalette palette,
    AppTypography typography,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: palette.fgTertiary,
          fontFamily: typography.monoFamily,
          fontSize: typography.crumbSize,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _entry(
    String trigger,
    String effect,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    return Container(
      constraints: BoxConstraints(minHeight: geometry.rowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: palette.divider,
            width: geometry.dividerThickness,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              trigger,
              style: TextStyle(
                color: palette.fgPrimary,
                fontFamily: typography.monoFamily,
                fontSize: typography.rowSize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              effect,
              style: TextStyle(
                color: palette.fgSecondary,
                fontFamily: typography.monoFamily,
                fontSize: typography.rowSize,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
