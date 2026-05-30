import 'package:flutter/material.dart';

import '../theme/app_geometry.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import '../widgets/press_feedback.dart';

/// Inline cheat-sheet of every gesture / control in the Void chrome. Reached from the ABOUT group of [VoidSettingsSheet].
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

    Widget group(String text) => _group(text, palette, typography);
    Widget entry(String trigger, String effect) =>
        _entry(trigger, effect, palette, typography, geometry);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(context, palette, typography),
            group('HERO'),
            entry('tap', 'play / pause the current track'),
            entry('swipe →', 'next track'),
            entry('swipe ←', 'previous track'),
            group('BROWSER'),
            entry('tap folder', 'enter folder'),
            entry('long-press folder', 'recursively shuffle all tracks'),
            entry('tap track', 'replace queue with the folder; play this'),
            entry('long-press track', 'play once, then resume previous queue'),
            entry('< ..', 'go up one folder (bottom of the list)'),
            entry('back button', 'go up one folder; exits at root'),
            group('CRUMB'),
            entry('long-press crumb', 'enter search across the whole library'),
            entry('tap a result', 'play it; the rest of the results queue up'),
            entry('× in search', 'leave search; original queue is restored'),
            group('TRANSPORT'),
            entry('icons', 'prev / play-pause / next'),
            entry('hairline above icons', 'tap or drag to seek'),
            entry('hairline at bottom', 'read-only progress'),
            group('CHROME'),
            entry('⋮ top-right', 'open settings'),
            entry('immersive', 'hide chrome — hero fills the screen'),
            entry('transport', 'collapse the prev/play/next strip'),
            entry('screen', 'cycle visualisation (spectrum / polo / dot / void)'),
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
          PressFeedback(
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
