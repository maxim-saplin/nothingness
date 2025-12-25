
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'models/spectrum_settings.dart';
import 'providers/audio_player_provider.dart';
import 'screens/media_controller_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nothingness/services/library_service.dart';
import 'package:nothingness/services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize just_audio_background
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.saplin.nothingness.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  // Initialize Hive
  await Hive.initFlutter();

  // Initialize LibraryService to restore file permissions
  await LibraryService().init();

  // Initialize audio player before app starts to avoid SoLoud init races
  final audioPlayerProvider = AudioPlayerProvider();
  await audioPlayerProvider.init();

  runApp(
    NothingApp(audioPlayerProvider: audioPlayerProvider),
  );
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
    SettingsService().loadSettings();
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
