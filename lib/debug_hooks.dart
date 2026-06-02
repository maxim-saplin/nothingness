import 'package:flutter/widgets.dart';

/// Thin seam between the app and the out-of-tree debug/automation harness
/// (dev/agent_service.dart). The app sets these in debug builds; the harness
/// reads them. Intentionally tiny and untyped (Object?) to avoid coupling.
class DebugHooks {
  DebugHooks._();
  static final GlobalKey screenshotBoundaryKey =
      GlobalKey(debugLabel: 'screenshotBoundary');
  static GlobalKey<NavigatorState>? navigatorKey;
  static Object? provider;          // PlaybackController
  static Object? libraryController; // LibraryController
  static bool Function()? immersiveLookup;
  static String? Function()? screenLookup;
  static Future<void> Function()? settingsOpener;
  /// Opens/closes the swipe-up library browser (drives the slide for QA of the
  /// overlay behavior). Set by VoidScreen in debug builds.
  static void Function(bool expanded)? browserExpander;
  /// Set by the harness; invoked by the app once init completes so the harness
  /// can register VM-service extensions. No-op if unset (production).
  static void Function(Object provider)? onAppReady;
}
