import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/theme_id.dart';
import 'models/theme_variant.dart';
import 'providers/audio_player_provider.dart';
import 'screens/media_controller_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/services/settings_service.dart';
import 'services/nothing_audio_handler.dart';
import 'testing/agent_service.dart';
import 'theme/themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Initialize LibraryService to restore file permissions
  await LibraryService().init();

  // Load user settings early so we can choose decoder before starting AudioService
  final settingsService = SettingsService();
  try {
    await settingsService.loadSettings();
  } catch (e) {
    debugPrint('[main] loadSettings failed, falling back to defaults: $e');
  }

  NothingAudioHandler? handler;
  if (Platform.isAndroid) {
    handler = await AudioService.init(
      builder: () => NothingAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.saplin.nothingness.channel.audio',
        androidNotificationChannelName: 'Audio playback',
        // Allow foreground service to stop when paused so the wake lock
        // and notification are released, saving battery.  The service is
        // re-promoted when playback resumes.
        androidStopForegroundOnPause: true,
      ),
    );
  }

  // Initialize audio player before app starts to avoid init races
  final audioPlayerProvider = AudioPlayerProvider(androidHandler: handler);
  await audioPlayerProvider.init();

  AgentService.register(provider: audioPlayerProvider);
  AgentService.registerNavigatorKey(rootNavigatorKey);

  runApp(NothingApp(audioPlayerProvider: audioPlayerProvider));
}

/// Top-level [NavigatorState] key used by [AgentService.closeSettingsSheet]
/// and similar route operations driven from the VM service. Kept at file
/// scope so it is created exactly once per process.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

class NothingApp extends StatefulWidget {
  const NothingApp({super.key, required this.audioPlayerProvider});

  final AudioPlayerProvider audioPlayerProvider;

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
    return ChangeNotifierProvider.value(
      value: widget.audioPlayerProvider,
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

              // On automotive OEM displays (e.g. Zeekr DHU) the platform
              // ignores statusBarIconBrightness/statusBarColor.  Draw a
              // Flutter scrim over the status-bar area so dark OEM icons
              // stay readable.  This sits outside ScaledLayout so it uses
              // raw screen coordinates.
              return ValueListenableBuilder<bool>(
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
            },
          );
        },
      ),
    );
  }
}

/// Rebuilds the [MaterialApp] when any of the three theme-driving notifiers
/// change. Listening to operating mode here keeps the tree wired even though
/// the mode does not directly affect [ThemeData] — downstream surfaces read it
/// via [SettingsService].
class _ThemeListener extends StatefulWidget {
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
  State<_ThemeListener> createState() => _ThemeListenerState();
}

class _ThemeListenerState extends State<_ThemeListener> {
  @override
  void initState() {
    super.initState();
    widget.themeIdNotifier.addListener(_onChanged);
    widget.themeVariantNotifier.addListener(_onChanged);
    widget.operatingModeNotifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.themeIdNotifier.removeListener(_onChanged);
    widget.themeVariantNotifier.removeListener(_onChanged);
    widget.operatingModeNotifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      widget.themeIdNotifier.value,
      widget.themeVariantNotifier.value,
    );
  }
}
