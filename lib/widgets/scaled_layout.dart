import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// A widget that scales its child based on the global uiScale setting.
/// This is useful for wrapping the entire screen or app sections to ensure
/// everything (including overlays/stacks) is scaled consistently.
class ScaledLayout extends StatelessWidget {
  final Widget child;

  const ScaledLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: SettingsService().uiScaleNotifier,
      builder: (context, rawUiScale, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;

            // Guard against zero constraints
            if (screenWidth <= 0 || screenHeight <= 0) {
              return this.child;
            }

            // Determine effective scale
            double uiScale = rawUiScale;
            if (uiScale <= 0 || !uiScale.isFinite) {
              // Auto mode: Calculate smart scale based on available width
              final dpr = MediaQuery.of(context).devicePixelRatio;
              uiScale = SettingsService().calculateSmartScaleForWidth(
                screenWidth,
                devicePixelRatio: dpr,
              );
            }

            uiScale = uiScale.clamp(0.5, 4.0);

            // If scale is effectively 1.0, just return the child
            if ((uiScale - 1.0).abs() < 0.01) {
              return this.child;
            }

            // Calculate logical size (what the content "sees")
            final logicalWidth = screenWidth / uiScale;
            final logicalHeight = screenHeight / uiScale;

            final mediaQuery = MediaQuery.of(context);

            return SizedBox(
              width: screenWidth,
              height: screenHeight,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Transform.scale(
                    scale: uiScale,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: logicalWidth,
                      height: logicalHeight,
                      child: MediaQuery(
                        data: mediaQuery.copyWith(
                          size: Size(logicalWidth, logicalHeight),
                          padding: mediaQuery.padding / uiScale,
                          viewInsets: mediaQuery.viewInsets / uiScale,
                          viewPadding: mediaQuery.viewPadding / uiScale,
                        ),
                        child: this.child,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
