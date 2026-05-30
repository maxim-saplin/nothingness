import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:provider/provider.dart';

import 'models/theme_id.dart';
import 'models/theme_variant.dart';
import 'screens/media_controller_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:nothingness/widgets/phone_frame.dart';
import 'services/automation_intent_service.dart';
import 'services/nothing_audio_handler.dart';
import 'services/playback_controller.dart';
import 'services/soloud_transport.dart';
import 'debug_hooks.dart';
import 'theme/themes.dart';

/// Boot stopwatch (B-008) — `main` entry to first frame; top-level so [_BootstrapAppState] stamps swap-from-splash against the same origin.
final Stopwatch _bootSw = Stopwatch()..start();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[boot] first-frame=${_bootSw.elapsedMilliseconds}ms');
  });
  debugPrint('[boot] runApp=${_bootSw.elapsedMilliseconds}ms');
  // B-008: keep `runApp` synchronous so the engine paints a cheap first frame (black [ColoredBox]) before heavy init; all awaits live in [_BootstrapAppState.initState].
  runApp(const _BootstrapApp());
}

/// Top-level [NavigatorState] key for [AgentService.closeSettingsSheet] and similar VM-service route ops; at file scope so it is created once per process.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

/// Splash + init host (B-008). Renders a black [ColoredBox] for the first frame while the heavy bootstrap (Hive, LibraryService, AudioService, PlaybackController) runs in a microtask, then swaps to the real [NothingApp]. Intentionally minimal so the first-frame `build` is effectively free.
class _BootstrapApp extends HookWidget {
  const _BootstrapApp();

  @override
  Widget build(BuildContext context) {
    final playbackController = useState<PlaybackController?>(null);

    // One-shot heavy bootstrap (empty deps → runs once). The microtask keeps it
    // off the synchronous build path so the splash frame renders first; the
    // `disposed` latch replaces the old State.mounted guard for the hot-restart race.
    useEffect(() {
      var disposed = false;

      Future<void> bootstrap() async {
        await Hive.initFlutter();

        // Restore file permissions.
        await LibraryService().init();

        // Load user settings early so we can choose decoder before starting AudioService.
        final settingsService = SettingsService();
        try {
          await settingsService.loadSettings();
        } catch (e) {
          debugPrint(
              '[main] loadSettings failed, falling back to defaults: $e');
        }

        // PlaybackController is the single source of truth on both platforms.
        // On Android the AudioService handler owns + inits the controller (and
        // observes it to drive the OS MediaSession); elsewhere we build a
        // transport + controller and init it here.
        final PlaybackController controller;
        if (Platform.isAndroid) {
          final handler = await AudioService.init(
            builder: () => NothingAudioHandler(),
            config: const AudioServiceConfig(
              androidNotificationChannelId:
                  'com.saplin.nothingness.channel.audio',
              androidNotificationChannelName: 'Audio playback',
              // Stop the foreground service when paused to release the wake lock/notification; re-promoted on resume.
              androidStopForegroundOnPause: true,
            ),
          );
          await handler.ready;
          controller = handler.controller;
        } else {
          controller = PlaybackController(transport: SoLoudTransport());
          await controller.init();
        }

        DebugHooks.navigatorKey = rootNavigatorKey;
        DebugHooks.provider = controller;
        DebugHooks.onAppReady?.call(controller);

        // B-031: wire Android intent-based automation (MacroDroid/Tasker/adb); drains any cold-start action that arrived before the handler attached.
        if (Platform.isAndroid) {
          unawaited(AutomationIntentService(controller).start());
        }

        if (disposed) {
          // Hot restart raced us; drop the half-built controller rather than leaving it dangling.
          controller.dispose();
          return;
        }
        debugPrint('[boot] swap=${_bootSw.elapsedMilliseconds}ms');
        playbackController.value = controller;
      }

      // Kick the heavy bootstrap off the synchronous build path; the microtask runs after the splash frame is rendered.
      scheduleMicrotask(bootstrap);

      return () => disposed = true;
    }, const []);

    final controller = playbackController.value;
    if (controller == null) {
      // Cheap-render path: no MaterialApp, theme, or fonts.
      return const ColoredBox(color: Color(0xFF000000));
    }
    return NothingApp(playbackController: controller);
  }
}

class NothingApp extends StatefulWidget {
  const NothingApp({super.key, required this.playbackController});

  final PlaybackController playbackController;

  @override
  State<NothingApp> createState() => _NothingAppState();
}

class _NothingAppState extends State<NothingApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();
    return ChangeNotifierProvider<PlaybackController>.value(
      value: widget.playbackController,
      child: _ThemeListener(
        themeIdNotifier: settings.themeIdNotifier,
        themeVariantNotifier: settings.themeVariantNotifier,
        operatingModeNotifier: settings.operatingModeNotifier,
        builder: (context, themeId, themeVariant) {
          return MaterialApp(
            title: 'Nothingness',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavigatorKey,
            themeMode: themeVariant.themeMode,
            theme: buildAppTheme(id: themeId, brightness: Brightness.light),
            darkTheme: buildAppTheme(id: themeId, brightness: Brightness.dark),
            home: const MediaControllerPage(),
            builder: (context, child) {
              if (child == null) return const SizedBox.shrink();

              // Debug only: AgentService rasterizes through this RepaintBoundary so drive.py can grab a PNG on desktop (where `adb screencap` doesn't apply).
              if (kDebugMode) {
                child = RepaintBoundary(
                  key: DebugHooks.screenshotBoundaryKey,
                  child: child,
                );
              }

              // Automotive OEM displays (e.g. Zeekr DHU) ignore statusBarIconBrightness/Color; draw a Flutter scrim over the status-bar area so dark OEM icons stay readable. Outside ScaledLayout so it uses raw screen coordinates.
              final Widget appWithChrome = ValueListenableBuilder<bool>(
                valueListenable: SettingsService().fullScreenNotifier,
                builder: (context, isFullScreen, appChild) {
                  if (isFullScreen) return appChild!;

                  final view = View.of(context);
                  final dpr = view.devicePixelRatio;
                  final logicalWidth = view.physicalSize.width / dpr;
                  if (!SettingsService.isLikelyAutomotive(logicalWidth, dpr)) {
                    return appChild!;
                  }

                  final statusBarHeight = MediaQuery.of(context).padding.top;
                  final brightness = MediaQuery.platformBrightnessOf(context);

                  return Stack(
                    children: [
                      appChild!,
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: statusBarHeight,
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: brightness == Brightness.dark
                                ? SettingsService.automotiveStatusBarScrimDark
                                : SettingsService.automotiveStatusBarScrimLight,
                          ),
                        ),
                      ),
                    ],
                  );
                },
                child: child,
              );

              // B-042 (debug only): render the app inside a letterboxed "phone frame" so portrait layout can be exercised on desktop; the MediaQuery size override makes layout/typography see phone dimensions for drive.py captures.
              if (!kDebugMode) return appWithChrome;
              return ValueListenableBuilder<Size?>(
                valueListenable: SettingsService().phoneFrameNotifier,
                builder: (context, frame, _) =>
                    PhoneFrame(frame: frame, child: appWithChrome),
              );
            },
          );
        },
      ),
    );
  }
}

/// Rebuilds the [MaterialApp] when any of the three theme-driving notifiers change. Operating mode is listened to here (though it doesn't affect [ThemeData]) to keep the tree wired; downstream surfaces read it via [SettingsService].
class _ThemeListener extends HookWidget {
  const _ThemeListener({
    required this.themeIdNotifier,
    required this.themeVariantNotifier,
    required this.operatingModeNotifier,
    required this.builder,
  });

  final ValueListenable<ThemeId> themeIdNotifier;
  final ValueListenable<ThemeVariant> themeVariantNotifier;
  final ValueListenable<Object> operatingModeNotifier;
  final Widget Function(BuildContext, ThemeId, ThemeVariant) builder;

  @override
  Widget build(BuildContext context) {
    final themeId = useValueListenable(themeIdNotifier);
    final themeVariant = useValueListenable(themeVariantNotifier);
    // Operating mode doesn't affect ThemeData, but we still subscribe so a
    // change rebuilds the tree (parity with the old explicit listener wiring).
    useValueListenable(operatingModeNotifier);
    return builder(context, themeId, themeVariant);
  }
}
