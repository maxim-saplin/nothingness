import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/screen_config.dart';
import 'models/spectrum_settings.dart';
import 'providers/audio_player_provider.dart';
import 'screens/spectrum_screen.dart';
import 'services/playback_controller.dart';
import 'services/playlist_store.dart';
import 'testing/test_harness.dart';
import 'testing/test_overlay.dart';

/// Test-only entrypoint for emulator integration tests.
///
/// - No AudioService / platform playback.
/// - Deterministic fake transport + controllable fileExists provider.
/// - Always-on test overlay for stable UI selectors + diagnostics.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final harness = TestHarness.instance;

  final playlist = PlaylistStore(
    boxOpener: (hive) => hive.openBox<dynamic>(
      'playlistBox_test_${DateTime.now().microsecondsSinceEpoch}',
    ),
  );

  final controller = PlaybackController(
    transport: harness.transport,
    playlist: playlist,
    debugPlaybackLogs: false,
    captureRecentLogs: true,
    preflightFileExists: true,
    fileExists: harness.fileExists,
  );
  await controller.init();
  harness.controller = controller;

  final audioPlayerProvider = AudioPlayerProvider.forTests(
    controller: controller,
    transport: harness.transport,
  );
  await audioPlayerProvider.init();

  runApp(
    ChangeNotifierProvider.value(
      value: audioPlayerProvider,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        ),
        home: Stack(
          children: [
            const SpectrumScreen(
              settings: SpectrumSettings(),
              config: SpectrumScreenConfig(),
              onToggleSettings: _noop,
            ),
            const TestOverlay(),
          ],
        ),
      ),
    ),
  );
}

void _noop() {}
