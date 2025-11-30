import 'dart:async';

import 'package:flutter/material.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import 'polo_screen.dart';
import 'spectrum_screen.dart';

class MediaControllerPage extends StatefulWidget {
  const MediaControllerPage({super.key});

  @override
  State<MediaControllerPage> createState() => _MediaControllerPageState();
}

class _MediaControllerPageState extends State<MediaControllerPage>
    with WidgetsBindingObserver {
  final _platformChannels = PlatformChannels();
  final _settingsService = SettingsService();

  SongInfo? _songInfo;
  List<double> _spectrumData = List.filled(32, 0.0);
  StreamSubscription<List<double>>? _spectrumSubscription;
  Timer? _songInfoTimer;

  bool _hasNotificationAccess = false;
  bool _hasAudioPermission = false;

  SpectrumSettings _settings = const SpectrumSettings();
  bool _isSettingsOpen = false;
  ScreenConfig _screenConfig = const SpectrumScreenConfig();
  bool _debugLayout = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadSettings();
    _settingsService.screenConfigNotifier.addListener(_handleScreenConfigChanged);
    _settingsService.debugLayoutNotifier.addListener(_handleDebugLayoutChanged);

    if (PlatformChannels.isAndroid) {
      _checkPermissions();
      _startSongInfoPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settingsService.screenConfigNotifier.removeListener(_handleScreenConfigChanged);
    _settingsService.debugLayoutNotifier.removeListener(_handleDebugLayoutChanged);
    _spectrumSubscription?.cancel();
    _songInfoTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && PlatformChannels.isAndroid) {
      _checkPermissions();
      _platformChannels.refreshSessions();
    }
  }

  void _handleScreenConfigChanged() {
    setState(() {
      _screenConfig = _settingsService.screenConfigNotifier.value;
    });
  }

  void _handleDebugLayoutChanged() {
    setState(() {
      _debugLayout = _settingsService.debugLayoutNotifier.value;
    });
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    setState(() {
      _settings = settings;
      _screenConfig = _settingsService.screenConfigNotifier.value;
    });
    // Update native side with loaded settings
    _platformChannels.updateSpectrumSettings(settings);
  }

  Future<void> _saveSettings(SpectrumSettings settings) async {
    await _settingsService.saveSettings(settings);

    setState(() {
      _settings = settings;
    });

    // Update native side
    _platformChannels.updateSpectrumSettings(settings);
  }

  Future<void> _checkPermissions() async {
    final notificationAccess =
        await _platformChannels.isNotificationAccessGranted();
    final audioPermission = await _platformChannels.hasAudioPermission();

    setState(() {
      _hasNotificationAccess = notificationAccess;
      _hasAudioPermission = audioPermission;
    });

    if (_hasAudioPermission && _spectrumSubscription == null) {
      _startSpectrumListening();
    }
  }

  void _startSongInfoPolling() {
    _songInfoTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _fetchSongInfo();
    });
    _fetchSongInfo();
  }

  Future<void> _fetchSongInfo() async {
    final songInfo = await _platformChannels.getSongInfo();
    setState(() {
      _songInfo = songInfo;
    });
  }

  void _startSpectrumListening() {
    _spectrumSubscription = _platformChannels.spectrumStream.listen((data) {
      setState(() {
        _spectrumData = data;
      });
    });
  }

  void _toggleSettings() {
    setState(() {
      _isSettingsOpen = !_isSettingsOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_screenConfig.type) {
      case ScreenType.spectrum:
        return SpectrumScreen(
          songInfo: _songInfo,
          spectrumData: _spectrumData,
          hasNotificationAccess: _hasNotificationAccess,
          hasAudioPermission: _hasAudioPermission,
          settings: _settings,
          platformChannels: _platformChannels,
          onToggleSettings: _toggleSettings,
          isSettingsOpen: _isSettingsOpen,
          onSettingsChanged: _saveSettings,
        );
      case ScreenType.polo:
        return PoloScreen(
          songInfo: _songInfo,
          config: _screenConfig as PoloScreenConfig,
          platformChannels: _platformChannels,
          onToggleSettings: _toggleSettings,
          isSettingsOpen: _isSettingsOpen,
          settings: _settings,
          onSettingsChanged: _saveSettings,
          debugLayout: _debugLayout,
        );
    }
  }
}
