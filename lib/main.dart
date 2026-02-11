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

              // ScaledLayout handles all UI scaling (in MediaControllerPage)
              // so just return child here.
              return child;
            },
          );
        },
      ),
    );
  }
}
