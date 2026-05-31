import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';

/// Shared outer container for hero visualisations embedded in the Void hero
/// slot. Pulls [AppPalette] from the theme to paint the [palette.background]
/// fill and, when [showDivider] is set, a 1-px bottom [palette.divider] border.
/// Per-hero differences (padding, alignment) are passed through verbatim so the
/// extraction is purely structural — no visual change.
class BaseHeroContainer extends StatelessWidget {
  const BaseHeroContainer({
    super.key,
    required this.child,
    this.showDivider = false,
    this.padding,
    this.alignment,
    this.width,
  });

  final Widget child;

  /// When true, paints a 1-px bottom border in [AppPalette.divider].
  final bool showDivider;

  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      width: width,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: palette.background,
        border: showDivider
            ? Border(bottom: BorderSide(color: palette.divider, width: 1))
            : null,
      ),
      child: child,
    );
  }
}
