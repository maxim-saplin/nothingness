import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../providers/audio_player_provider.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../services/logging_service.dart';
import '../widgets/library_panel.dart';
import '../widgets/scaled_layout.dart';
import 'dot_screen.dart';
import 'log_screen.dart';
import 'polo_screen.dart';
import 'settings_screen.dart';
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
  SongInfo? _micSongInfo;
  List<double> _micSpectrumData = List.filled(32, 0.0);
  StreamSubscription<List<double>>? _spectrumSubscription;
  Timer? _songInfoTimer;

  bool _hasNotificationAccess = false;
  bool _hasAudioPermission = false;

  SpectrumSettings _settings = const SpectrumSettings();
  bool _isSettingsOpen = false;
  ScreenConfig _screenConfig = const SpectrumScreenConfig();
  bool _debugLayout = false;
  bool _isFullScreen = false;
  bool _isLibraryOpen = false;
  bool _isAppInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bootstrap();
    _settingsService.screenConfigNotifier.addListener(
      _handleScreenConfigChanged,
    );
    _settingsService.debugLayoutNotifier.addListener(_handleDebugLayoutChanged);
    _settingsService.fullScreenNotifier.addListener(_handleFullScreenChanged);

    if (PlatformChannels.isAndroid) {
      _checkPermissions();
    }
  }

  Future<void> _bootstrap() async {
    await _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settingsService.screenConfigNotifier.removeListener(
      _handleScreenConfigChanged,
    );
    _settingsService.debugLayoutNotifier.removeListener(
      _handleDebugLayoutChanged,
    );
    _settingsService.fullScreenNotifier.removeListener(
      _handleFullScreenChanged,
    );
    _spectrumSubscription?.cancel();
    _songInfoTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!PlatformChannels.isAndroid) return;

    if (state == AppLifecycleState.resumed) {
      // App resumed: restore spectrum processing and refresh permissions
      _isAppInBackground = false;
      _platformChannels.refreshSessions();
      // _checkPermissions will call _attachSpectrumSource after checking permissions
      _checkPermissions();
      _syncSongInfoSource(_settings);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App backgrounded: stop spectrum processing to save battery
      _isAppInBackground = true;
      _spectrumSubscription?.cancel();
      _songInfoTimer?.cancel();
      final player = context.read<AudioPlayerProvider>();
      player.setCaptureEnabled(false);
    }
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

  void _handleDebugLayoutChanged() {
    setState(() {
      _debugLayout = _settingsService.debugLayoutNotifier.value;
    });
  }

  void _handleFullScreenChanged() {
    setState(() {
      _isFullScreen = _settingsService.fullScreenNotifier.value;
    });
  }

  void _syncSongInfoSource(SpectrumSettings settings) {
    _songInfoTimer?.cancel();
    // Don't start song info timer if app is in background
    if (_isAppInBackground) {
      return;
    }

    if (settings.audioSource == AudioSourceMode.microphone &&
        PlatformChannels.isAndroid) {
      _songInfoTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
        _fetchSongInfo();
      });
      _fetchSongInfo();
    } else {
      setState(() {
        _micSongInfo = null; // Provider handles player song info
      });
    }
  }

  void _attachSpectrumSource(SpectrumSettings settings) {
    // Don't start spectrum processing if app is in background
    if (_isAppInBackground) {
      return;
    }

    _spectrumSubscription?.cancel();

    final player = context.read<AudioPlayerProvider>();

    if (settings.audioSource == AudioSourceMode.player) {
      player.updateSpectrumSettings(settings);
      player.setCaptureEnabled(true);
      setState(() {
        _micSpectrumData = List.filled(32, 0.0);
      });
    } else {
      player.setCaptureEnabled(false);
      if (_hasAudioPermission) {
        _spectrumSubscription = _platformChannels.spectrumStream().listen((
          data,
        ) {
          setState(() {
            _micSpectrumData = data;
          });
        });
      } else {
        setState(() {
          _micSpectrumData = List.filled(32, 0.0);
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    setState(() {
      _settings = settings;
      _screenConfig = _settingsService.screenConfigNotifier.value;
      _isFullScreen = _settingsService.fullScreenNotifier.value;
    });
    _syncSongInfoSource(settings);
    _attachSpectrumSource(settings);
    // Update native side with loaded settings
    _platformChannels.updateSpectrumSettings(settings);
    _platformChannels.updateEqualizerSettings(
      _settingsService.eqSettingsNotifier.value,
    );
  }

  Future<void> _saveSettings(SpectrumSettings settings) async {
    await _settingsService.saveSettings(settings);

    setState(() {
      _settings = settings;
    });

    _syncSongInfoSource(settings);
    _attachSpectrumSource(settings);

    // Update native side
    _platformChannels.updateSpectrumSettings(settings);
  }

  Future<void> _checkPermissions() async {
    final notificationAccess = await _platformChannels
        .isNotificationAccessGranted();
    final audioPermission = await _platformChannels.hasAudioPermission();

    setState(() {
      _hasNotificationAccess = notificationAccess;
      _hasAudioPermission = audioPermission;
    });

    _attachSpectrumSource(_settings);
  }

  Future<void> _fetchSongInfo() async {
    final songInfo = await _platformChannels.getSongInfo();
    setState(() {
      _micSongInfo = songInfo;
    });
  }

  void _toggleSettings() {
    setState(() {
      _isSettingsOpen = !_isSettingsOpen;
    });
  }

  Future<void> _requestAudioPermission() async {
    // Request all required permissions via permission_handler
    await [
      Permission.storage,
      Permission.audio,
      Permission.microphone,
    ].request();

    // Also call platform channel request for legacy/specific handling if needed
    await _platformChannels.requestAudioPermission();
    await _checkPermissions();
  }

  Future<void> _openNotificationSettings() async {
    await _platformChannels.openNotificationSettings();
    await Future.delayed(const Duration(milliseconds: 500));
    await _checkPermissions();
  }

  void _openLibrary() {
    setState(() {
      _isLibraryOpen = true;
    });
  }

  Future<void> _openLogs() async {
    LoggingService().log(tag: 'UI', message: 'Open Logs screen');
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LogScreen()));
  }

  void _closeLibrary() {
    setState(() {
      _isLibraryOpen = false;
    });
  }

  Widget _buildLibraryHandle(BuildContext context) {
    // Respect bottom padding (e.g. nav bar) so the arrow isn't covered
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: 12 + bottomPadding,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _isLibraryOpen ? _closeLibrary : _openLibrary,
          child: Icon(
            _isLibraryOpen
                ? Icons.keyboard_arrow_down_rounded
                : Icons.keyboard_arrow_up_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryPanel(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.65;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: _isLibraryOpen ? 0 : -height,
      height: height,
      child: LibraryPanel(onClose: _closeLibrary, isOpen: _isLibraryOpen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaledLayout(
      child: Builder(
        builder: (context) {
          // Calculate panel width based on logical size from ScaledLayout
          final logicalScreenWidth = MediaQuery.of(context).size.width;
          final panelWidth = logicalScreenWidth > 900
              ? logicalScreenWidth / 3
              : (logicalScreenWidth / 2).clamp(300.0, 400.0);

          return GestureDetector(
            onVerticalDragUpdate: (details) {
              final delta = details.primaryDelta ?? 0;
              if (delta < -8) {
                _openLibrary();
              } else if (delta > 8) {
                _closeLibrary();
              }
            },
            child: Stack(
              children: [
                // Current Screen
                _buildCurrentScreen(),

                // Library panel
                _buildLibraryPanel(context),
                _buildLibraryHandle(context),

                // Settings Panel Overlay
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  top: 0,
                  bottom: 0,
                  right: _isSettingsOpen ? 0 : -panelWidth,
                  width: panelWidth,
                  child: SettingsScreen(
                    settings: _settings,
                    onSettingsChanged: _saveSettings,
                    uiScale: _settingsService.uiScaleNotifier.value,
                    onUiScaleChanged: (scale) =>
                        _settingsService.saveUiScale(scale),
                    fullScreen: _isFullScreen,
                    onFullScreenChanged: (val) =>
                        _settingsService.setFullScreen(val, save: true),
                    onClose: _toggleSettings,
                    hasNotificationAccess: _hasNotificationAccess,
                    hasAudioPermission: _hasAudioPermission,
                    onRequestNotificationAccess: _openNotificationSettings,
                    onRequestAudioPermission: _requestAudioPermission,
                    onShowLogs: _openLogs,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCurrentScreen() {
    final player = context.watch<AudioPlayerProvider>();
    final songInfo =
        _settings.audioSource == AudioSourceMode.microphone &&
            PlatformChannels.isAndroid
        ? _micSongInfo
        : player.songInfo;
    final spectrumData = _settings.audioSource == AudioSourceMode.player
        ? player.spectrumData
        : _micSpectrumData;

    switch (_screenConfig.type) {
      case ScreenType.spectrum:
        return SpectrumScreen(
          settings: _settings,
          config: _screenConfig as SpectrumScreenConfig,
          onToggleSettings: _toggleSettings,
          externalSongInfo: songInfo,
          externalSpectrumData: spectrumData,
        );
      case ScreenType.polo:
        return PoloScreen(
          config: _screenConfig as PoloScreenConfig,
          onToggleSettings: _toggleSettings,
          settings: _settings,
          debugLayout: _debugLayout,
          externalSongInfo: songInfo,
        );
      case ScreenType.dot:
        return DotScreen(
          settings: _settings,
          config: _screenConfig as DotScreenConfig,
          onToggleSettings: _toggleSettings,
          externalSongInfo: songInfo,
          externalSpectrumData: spectrumData,
        );
    }
  }
}
