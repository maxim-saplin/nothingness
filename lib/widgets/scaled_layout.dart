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
      builder: (context, rawUiScale, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            if (screenWidth <= 0 || screenHeight <= 0) {
              return child; // guard against zero constraints
            }

            var uiScale = rawUiScale;
            if (uiScale <= 0 || !uiScale.isFinite) {
              // Auto mode: smart scale from available width.
              uiScale = SettingsService().calculateSmartScaleForWidth(
                screenWidth,
                devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
              );
            }
            // B-044: ceiling matches the slider max / auto-scale clamp (3.0);
            // a higher ceiling overflowed the now-playing header.
            uiScale = uiScale.clamp(0.5, 3.0);
            if ((uiScale - 1.0).abs() < 0.01) {
              return child; // effectively unscaled
            }

            // Logical size the scaled content "sees".
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
                        child: child,
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
