import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/spectrum_settings.dart';
import 'providers/audio_player_provider.dart';
import 'screens/media_controller_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/services/settings_service.dart';
import 'services/nothing_audio_handler.dart';
import 'testing/agent_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Initialize LibraryService to restore file permissions
  await LibraryService().init();

  // Load user settings early so we can choose decoder before starting AudioService
  final settingsService = SettingsService();
  await settingsService.loadSettings();

  NothingAudioHandler? handler;
  if (Platform.isAndroid) {
    handler = await AudioService.init(
      builder: () => NothingAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.saplin.nothingness.channel.audio',
        androidNotificationChannelName: 'Audio playback',
        // Keep the foreground service alive while paused.
        //
        // Some devices will otherwise stop the service after being paused in the
        // background, which can invalidate the player/audio session. The user
        // then returns to the app and "Play" appears to do nothing.
        androidStopForegroundOnPause: false,
      ),
    );
  }

  // Initialize audio player before app starts to avoid init races
  final audioPlayerProvider = AudioPlayerProvider(androidHandler: handler);
  await audioPlayerProvider.init();

  AgentService.register(provider: audioPlayerProvider);

  runApp(NothingApp(audioPlayerProvider: audioPlayerProvider));
}

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
    return ChangeNotifierProvider.value(
      value: widget.audioPlayerProvider,
      child: ValueListenableBuilder<SpectrumSettings>(
        valueListenable: SettingsService().settingsNotifier,
        builder: (context, settings, child) {
          return MaterialApp(
            title: 'Nothingness',
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: const Color(0xFF0A0A0F),
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF00FF88),
                secondary: Color(0xFFFF6B35),
                surface: Color(0xFF12121A),
              ),
            ),
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
