import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/operating_mode.dart';
import '../models/screen_config.dart';
import '../models/spectrum_settings.dart';
import '../providers/audio_player_provider.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../testing/agent_service.dart';
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
  // Per-session latch so we don't push the user into the Android Settings
  // "Notification access" page every time they re-toggle background mode
  // (B-006). Reset on cold launch via natural state recreation.
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

    // The active screen is sourced from settings — kept here so transitions
    // away from Void don't leave a stale lookup behind.
    AgentService.registerScreenLookup(_currentScreenName);
    AgentService.registerSettingsOpener(_openSettingsForActiveScreen);

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

  /// Settings-opener closure exposed to [AgentService]. All four
  /// visualisations now share the Void chrome, so there's only one sheet
  /// — [VoidSettingsSheet].
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
    AgentService.registerSettingsOpener(null);
    AgentService.registerScreenLookup(null);
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
    // Re-apply the overlay style so status-bar icons match the new theme.
    _settingsService.setFullScreen(
      _settingsService.fullScreenNotifier.value,
      save: false,
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    // Developer Optimization:
    // When editing PoloScreenConfig constructor defaults (coordinates),
    // we want Hot Reload to immediately apply them.
    // We force a fresh instance creation to pick up the new default values.
    if (_screenConfig.type == ScreenType.polo) {
      // Use the constructor to get new default values from source code
      final newConfig = const PoloScreenConfig();
      // Update the service, which notifies this widget to rebuild
      _settingsService.screenConfigNotifier.value = newConfig;
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

  /// Mirror SpectrumSettings changes (bar count, decay, colour scheme, etc.)
  /// down to the audio pipeline and pass the fresh snapshot to VoidScreen so
  /// the hero re-renders. Without this, cycling a knob in the settings sheet
  /// writes the value to prefs but the visualisation keeps using the old one.
  void _handleSpectrumSettingsChanged() {
    if (!mounted) return;
    final next = _settingsService.settingsNotifier.value;
    setState(() => _settings = next);
    if (_operatingMode == OperatingMode.own && !_isAppInBackground) {
      try {
        context.read<AudioPlayerProvider>().updateSpectrumSettings(next);
      } catch (_) {
        // Provider not in scope yet (during first-frame bootstrap) — fine.
      }
    }
    _platformChannels.updateSpectrumSettings(next);
  }

  /// Re-wire spectrum source when the user toggles operating mode.
  ///
  /// On a switch into background mode we also pause the app's own playback
  /// (intentionally — not torn down) so the OS does not show two now-playing
  /// cards. The handler is kept idle rather than disposed so flipping back to
  /// own mode is instant and the queue / position survives the round-trip.
  /// When entering background mode for the first time we request mic +
  /// notification-listener access.
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
    // Request mic permission silently if not yet granted.
    if (!await Permission.microphone.isGranted) {
      await Permission.microphone.request();
    }
    // Notification-listener access can't be granted via permission_handler —
    // it requires the user to flip the toggle in system settings. We only
    // prompt by opening that screen the FIRST time per session (B-006);
    // subsequent toggles don't re-hijack the screen. The settings sheet
    // surfaces "notification listener" with a tap-to-re-prompt entry.
    final hasListener = await _platformChannels.isNotificationAccessGranted();
    if (!hasListener && !_promptedNotifThisSession) {
      _promptedNotifThisSession = true;
      await _platformChannels.openNotificationSettings();
    }
    await _checkPermissions();
  }

  /// Toggles the player's spectrum capture based on the active mode.
  /// Background mode disables player capture; the mic-spectrum stream the
  /// legacy chrome used to subscribe to is no longer routed into heroes —
  /// background-mode visualisation is deferred (heroes show silence). Own
  /// mode re-enables capture and pushes the latest spectrum settings.
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

    // If we start up in background mode, surface the permission prompts on
    // first run so the user can complete setup without digging through menus.
    if (_operatingMode == OperatingMode.background &&
        PlatformChannels.isAndroid) {
      await _ensureBackgroundPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    if (!mounted) return;
    // On Android 13+ (API 33) the media notification served by audio_service
    // is silently dropped unless POST_NOTIFICATIONS is granted. Request once
    // on startup so lock-screen / shade controls work without the user having
    // to dig through Settings. The plugin is idempotent — no dialog after the
    // first decision.
    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }
    _attachSpectrumSource();
  }

  @override
  Widget build(BuildContext context) {
    // The Void chrome wraps every visualisation now. MediaControllerPage
    // keeps the audio-mode plumbing (operating mode, spectrum source,
    // permission bootstrap, app-lifecycle hooks) but no longer paints any
    // chrome of its own; UI scale lives inside ScaledLayout, the rest is
    // owned by VoidScreen.
    return ScaledLayout(
      child: VoidScreen(config: _screenConfig, settings: _settings),
    );
  }
}
