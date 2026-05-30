import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/operating_mode.dart';
import '../models/screen_config.dart';
import '../providers/audio_player_provider.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../debug_hooks.dart';
import '../widgets/scaled_layout.dart';
import '../widgets/void_settings_sheet.dart';
import 'void_screen.dart';

/// Fires [onReassemble] on hot reload (Flutter's `State.reassemble` seam, which
/// has no first-class hook). Used to refresh source-derived config defaults.
void _useReassemble(VoidCallback onReassemble) {
  use(_ReassembleHook(onReassemble));
}

class _ReassembleHook extends Hook<void> {
  const _ReassembleHook(this.onReassemble);
  final VoidCallback onReassemble;

  @override
  _ReassembleHookState createState() => _ReassembleHookState();
}

class _ReassembleHookState extends HookState<void, _ReassembleHook> {
  @override
  void build(BuildContext context) {}

  @override
  void reassemble() => hook.onReassemble();
}

class MediaControllerPage extends HookWidget {
  const MediaControllerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final platformChannels = useMemoized(PlatformChannels.new);
    final settingsService = useMemoized(SettingsService.new);

    // Per-session latch so re-toggling background mode doesn't re-open the
    // Android "Notification access" page (B-006).
    final promptedNotifThisSession = useRef(false);
    final isAppInBackground = useRef(false);

    // Build reacts to settings + active screen straight off the notifiers
    // (their own source of truth), so handlers only run side effects.
    final settings = useValueListenable(settingsService.settingsNotifier);
    final screenConfig = useValueListenable(
      settingsService.screenConfigNotifier,
    );

    String currentScreenName() {
      switch (settingsService.screenConfigNotifier.value.type) {
        case ScreenType.spectrum:
          return 'spectrum';
        case ScreenType.polo:
          return 'polo';
        case ScreenType.dot:
          return 'dot';
        case ScreenType.void_:
          return 'void';
      }
    }

    /// Toggle the player's spectrum capture: own mode re-enables capture and
    /// pushes latest settings; background mode disables it (background
    /// visualisation deferred — heroes show silence).
    void attachSpectrumSource() {
      if (isAppInBackground.value) return;
      final player = context.read<AudioPlayerProvider>();
      if (settingsService.operatingModeNotifier.value == OperatingMode.own) {
        player.updateSpectrumSettings(settingsService.settingsNotifier.value);
        player.setCaptureEnabled(true);
      } else {
        player.setCaptureEnabled(false);
      }
    }

    Future<void> checkPermissions() async {
      if (!context.mounted) return;
      // Android 13+ (API 33) drops the media notification without
      // POST_NOTIFICATIONS; request once on startup (idempotent).
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }
      attachSpectrumSource();
    }

    Future<void> ensureBackgroundPermissions() async {
      if (!await Permission.microphone.isGranted) {
        await Permission.microphone.request();
      }
      // Notification-listener access needs a manual settings toggle; open it
      // only the FIRST time per session (B-006).
      final hasListener = await platformChannels.isNotificationAccessGranted();
      if (!hasListener && !promptedNotifThisSession.value) {
        promptedNotifThisSession.value = true;
        await platformChannels.openNotificationSettings();
      }
      await checkPermissions();
    }

    /// Settings-opener exposed to [AgentService]; all visualisations share the
    /// single [VoidSettingsSheet].
    Future<void> openSettingsForActiveScreen() async {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const VoidSettingsSheet()),
      );
    }

    // DebugHooks wiring (set on mount, cleared on unmount).
    useEffect(() {
      DebugHooks.screenLookup = currentScreenName;
      DebugHooks.settingsOpener = openSettingsForActiveScreen;
      return () {
        DebugHooks.settingsOpener = null;
        DebugHooks.screenLookup = null;
      };
    }, const []);

    // Mirror SpectrumSettings changes down to the audio pipeline and into
    // VoidScreen so the hero re-renders.
    useEffect(() {
      void handleSpectrumSettingsChanged() {
        if (!context.mounted) return;
        final next = settingsService.settingsNotifier.value;
        if (settingsService.operatingModeNotifier.value == OperatingMode.own &&
            !isAppInBackground.value) {
          try {
            context.read<AudioPlayerProvider>().updateSpectrumSettings(next);
          } catch (_) {
            // Provider not in scope yet during first-frame bootstrap — fine.
          }
        }
        platformChannels.updateSpectrumSettings(next);
      }

      settingsService.settingsNotifier.addListener(
        handleSpectrumSettingsChanged,
      );
      return () => settingsService.settingsNotifier.removeListener(
            handleSpectrumSettingsChanged,
          );
    }, const []);

    // Re-wire spectrum source on operating-mode toggle: background mode pauses
    // (not tears down) own playback so the OS shows one now-playing card; first
    // entry also requests mic + notification-listener access.
    useEffect(() {
      Future<void> handleOperatingModeChanged() async {
        final mode = settingsService.operatingModeNotifier.value;
        if (!context.mounted) return;
        if (mode == OperatingMode.background) {
          try {
            final player = context.read<AudioPlayerProvider>();
            if (player.isPlaying) {
              await player.playPause();
            }
          } catch (_) {
            // Provider not in scope — fine; nothing to pause.
          }
          if (PlatformChannels.isAndroid) {
            await ensureBackgroundPermissions();
          }
        }
        attachSpectrumSource();
      }

      settingsService.operatingModeNotifier.addListener(
        handleOperatingModeChanged,
      );
      return () => settingsService.operatingModeNotifier.removeListener(
            handleOperatingModeChanged,
          );
    }, const []);

    // Bootstrap: load persisted settings + push them through the pipeline.
    useEffect(() {
      var active = true;
      Future<void> loadSettings() async {
        final loaded = await settingsService.loadSettings();
        if (!active) return;
        attachSpectrumSource();
        platformChannels.updateSpectrumSettings(loaded);
        platformChannels.updateEqualizerSettings(
          settingsService.eqSettingsNotifier.value,
        );

        // Cold-start in background mode: surface permission prompts up front.
        if (settingsService.operatingModeNotifier.value ==
                OperatingMode.background &&
            PlatformChannels.isAndroid) {
          await ensureBackgroundPermissions();
        }
      }

      loadSettings();
      if (PlatformChannels.isAndroid) {
        checkPermissions();
      }
      return () => active = false;
    }, const []);

    // App lifecycle (replaces WidgetsBindingObserver.didChangeAppLifecycleState).
    useOnAppLifecycleStateChange((previous, state) {
      if (!PlatformChannels.isAndroid) return;
      final player = context.read<AudioPlayerProvider>();
      if (state == AppLifecycleState.resumed) {
        isAppInBackground.value = false;
        platformChannels.refreshSessions();
        attachSpectrumSource();
        checkPermissions();
        player.resumeTimers();
      } else if (state == AppLifecycleState.paused) {
        isAppInBackground.value = true;
        player.setCaptureEnabled(false);
        player.suspendTimers();
      }
    });

    // Re-apply overlay style so status-bar icons match the new theme.
    useOnPlatformBrightnessChange((previous, current) {
      settingsService.setFullScreen(
        settingsService.fullScreenNotifier.value,
        save: false,
      );
    });

    // Hot Reload: rebuild PoloScreenConfig so edited constructor defaults
    // (coordinates) are picked up immediately.
    _useReassemble(() {
      if (settingsService.screenConfigNotifier.value.type == ScreenType.polo) {
        settingsService.screenConfigNotifier.value = const PoloScreenConfig();
        debugPrint(
          '[Hot Reload] PoloScreenConfig refreshed from source defaults',
        );
      }
    });

    // No chrome of its own: this page keeps the audio-mode plumbing; Void chrome
    // wraps every visualisation, UI scale lives in ScaledLayout.
    return ScaledLayout(
      child: VoidScreen(config: screenConfig, settings: settings),
    );
  }
}
