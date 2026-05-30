import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/operating_mode.dart';
import '../models/screen_config.dart';
import '../models/spectrum_settings.dart';
import '../providers/audio_player_provider.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../debug_hooks.dart';
import '../widgets/scaled_layout.dart';
import '../widgets/void_settings_sheet.dart';
import 'void_screen.dart';

class MediaControllerPage extends StatefulWidget {
  const MediaControllerPage({super.key});

  @override
  State<MediaControllerPage> createState() => _MediaControllerPageState();
}

class _MediaControllerPageState extends State<MediaControllerPage>
    with WidgetsBindingObserver {
  final _platformChannels = PlatformChannels();
  final _settingsService = SettingsService();
  // Per-session latch so re-toggling background mode doesn't re-open the Android "Notification access" page (B-006).
  bool _promptedNotifThisSession = false;

  SpectrumSettings _settings = const SpectrumSettings();
  OperatingMode _operatingMode = OperatingMode.own;
  ScreenConfig _screenConfig = const SpectrumScreenConfig();
  bool _isAppInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bootstrap();
    _settingsService.screenConfigNotifier.addListener(
      _handleScreenConfigChanged,
    );
    _settingsService.operatingModeNotifier.addListener(
      _handleOperatingModeChanged,
    );
    _settingsService.settingsNotifier.addListener(_handleSpectrumSettingsChanged);

    DebugHooks.screenLookup = _currentScreenName;
    DebugHooks.settingsOpener = _openSettingsForActiveScreen;

    if (PlatformChannels.isAndroid) {
      _checkPermissions();
    }
  }

  String _currentScreenName() {
    switch (_screenConfig.type) {
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

  /// Settings-opener exposed to [AgentService]; all visualisations share the single [VoidSettingsSheet].
  Future<void> _openSettingsForActiveScreen() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VoidSettingsSheet()),
    );
  }

  Future<void> _bootstrap() async {
    await _loadSettings();
  }

  @override
  void dispose() {
    DebugHooks.settingsOpener = null;
    DebugHooks.screenLookup = null;
    WidgetsBinding.instance.removeObserver(this);
    _settingsService.screenConfigNotifier.removeListener(
      _handleScreenConfigChanged,
    );
    _settingsService.settingsNotifier.removeListener(
      _handleSpectrumSettingsChanged,
    );
    _settingsService.operatingModeNotifier.removeListener(
      _handleOperatingModeChanged,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!PlatformChannels.isAndroid) return;

    final player = context.read<AudioPlayerProvider>();
    if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      _platformChannels.refreshSessions();
      _attachSpectrumSource();
      _checkPermissions();
      player.resumeTimers();
    } else if (state == AppLifecycleState.paused) {
      _isAppInBackground = true;
      player.setCaptureEnabled(false);
      player.suspendTimers();
    }
  }

  @override
  void didChangePlatformBrightness() {
    // Re-apply overlay style so status-bar icons match the new theme.
    _settingsService.setFullScreen(
      _settingsService.fullScreenNotifier.value,
      save: false,
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot Reload: rebuild PoloScreenConfig so edited constructor defaults (coordinates) are picked up immediately.
    if (_screenConfig.type == ScreenType.polo) {
      _settingsService.screenConfigNotifier.value = const PoloScreenConfig();
      debugPrint(
        '[Hot Reload] PoloScreenConfig refreshed from source defaults',
      );
    }
  }

  void _handleScreenConfigChanged() {
    setState(() {
      _screenConfig = _settingsService.screenConfigNotifier.value;
    });
  }

  /// Mirror SpectrumSettings changes down to the audio pipeline and into VoidScreen so the hero re-renders.
  void _handleSpectrumSettingsChanged() {
    if (!mounted) return;
    final next = _settingsService.settingsNotifier.value;
    setState(() => _settings = next);
    if (_operatingMode == OperatingMode.own && !_isAppInBackground) {
      try {
        context.read<AudioPlayerProvider>().updateSpectrumSettings(next);
      } catch (_) {
        // Provider not in scope yet during first-frame bootstrap — fine.
      }
    }
    _platformChannels.updateSpectrumSettings(next);
  }

  /// Re-wire spectrum source on operating-mode toggle: background mode pauses (not tears down) own playback so the OS shows one now-playing card; first entry also requests mic + notification-listener access.
  Future<void> _handleOperatingModeChanged() async {
    final mode = _settingsService.operatingModeNotifier.value;
    if (!mounted) return;
    setState(() => _operatingMode = mode);

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
        await _ensureBackgroundPermissions();
      }
    }
    _attachSpectrumSource();
  }

  Future<void> _ensureBackgroundPermissions() async {
    if (!await Permission.microphone.isGranted) {
      await Permission.microphone.request();
    }
    // Notification-listener access needs a manual settings toggle; open it only the FIRST time per session (B-006).
    final hasListener = await _platformChannels.isNotificationAccessGranted();
    if (!hasListener && !_promptedNotifThisSession) {
      _promptedNotifThisSession = true;
      await _platformChannels.openNotificationSettings();
    }
    await _checkPermissions();
  }

  /// Toggle the player's spectrum capture: own mode re-enables capture and pushes latest settings; background mode disables it (background visualisation deferred — heroes show silence).
  void _attachSpectrumSource() {
    if (_isAppInBackground) return;
    final player = context.read<AudioPlayerProvider>();
    if (_operatingMode == OperatingMode.own) {
      player.updateSpectrumSettings(_settings);
      player.setCaptureEnabled(true);
    } else {
      player.setCaptureEnabled(false);
    }
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    setState(() {
      _settings = settings;
      _operatingMode = _settingsService.operatingModeNotifier.value;
      _screenConfig = _settingsService.screenConfigNotifier.value;
    });
    _attachSpectrumSource();
    _platformChannels.updateSpectrumSettings(settings);
    _platformChannels.updateEqualizerSettings(
      _settingsService.eqSettingsNotifier.value,
    );

    // Cold-start in background mode: surface permission prompts up front.
    if (_operatingMode == OperatingMode.background &&
        PlatformChannels.isAndroid) {
      await _ensureBackgroundPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    if (!mounted) return;
    // Android 13+ (API 33) drops the media notification without POST_NOTIFICATIONS; request once on startup (idempotent).
    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }
    _attachSpectrumSource();
  }

  @override
  Widget build(BuildContext context) {
    // No chrome of its own: this page keeps the audio-mode plumbing; Void chrome wraps every visualisation, UI scale lives in ScaledLayout.
    return ScaledLayout(
      child: VoidScreen(config: _screenConfig, settings: _settings),
    );
  }
}
