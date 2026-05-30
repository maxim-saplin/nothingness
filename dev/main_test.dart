import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/screens/void_screen.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/playlist_store.dart';
import 'test_harness.dart';
import 'test_overlay.dart';

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

  runApp(
    ChangeNotifierProvider<PlaybackController>.value(
      value: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        ),
        home: Stack(
          children: const [
            VoidScreen(
              config: SpectrumScreenConfig(),
              settings: SpectrumSettings(),
            ),
            TestOverlay(),
          ],
        ),
      ),
    ),
  );
}
