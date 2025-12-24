import 'dart:async';

import 'package:flutter/material.dart';

import '../models/screen_config.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/audio_player_service.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../widgets/library_panel.dart';
import '../widgets/scaled_layout.dart';
import 'dot_screen.dart';
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
  final _audioPlayerService = AudioPlayerService();

  SongInfo? _songInfo;
  List<double> _spectrumData = List.filled(32, 0.0);
  StreamSubscription<List<double>>? _spectrumSubscription;
  StreamSubscription<List<double>>? _playerSpectrumSubscription;
  VoidCallback? _songInfoListener;
  Timer? _songInfoTimer;

  bool _hasNotificationAccess = false;
  bool _hasAudioPermission = false;

  SpectrumSettings _settings = const SpectrumSettings();
  bool _isSettingsOpen = false;
  ScreenConfig _screenConfig = const SpectrumScreenConfig();
  bool _debugLayout = false;
  bool _isFullScreen = false;
  bool _isLibraryOpen = false;

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
    await _initPlayer();
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
    _playerSpectrumSubscription?.cancel();
    _songInfoTimer?.cancel();
    if (_songInfoListener != null) {
      _audioPlayerService.songInfoNotifier.removeListener(_songInfoListener!);
    }
    _audioPlayerService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && PlatformChannels.isAndroid) {
      _checkPermissions();
      _platformChannels.refreshSessions();
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
    if (settings.audioSource == AudioSourceMode.microphone &&
        PlatformChannels.isAndroid) {
      _songInfoTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
        _fetchSongInfo();
      });
      _fetchSongInfo();
    } else {
      setState(() {
        _songInfo = _audioPlayerService.songInfoNotifier.value;
      });
    }
  }

  void _attachSpectrumSource(SpectrumSettings settings) {
    _spectrumSubscription?.cancel();
    _playerSpectrumSubscription?.cancel();

    if (settings.audioSource == AudioSourceMode.player) {
      _audioPlayerService.updateSpectrumSettings(settings);
      _audioPlayerService.setCaptureEnabled(true);
      _playerSpectrumSubscription =
          _audioPlayerService.spectrumStream.listen((data) {
        setState(() {
          _spectrumData = data;
        });
      });
    } else {
      _audioPlayerService.setCaptureEnabled(false);
      if (_hasAudioPermission) {
        _spectrumSubscription =
            _platformChannels.spectrumStream.listen((data) {
          setState(() {
            _spectrumData = data;
          });
        });
      } else {
        setState(() {
          _spectrumData = List.filled(32, 0.0);
        });
      }
    }
  }

  Future<void> _initPlayer() async {
    await _audioPlayerService.init();
    _songInfo = _audioPlayerService.songInfoNotifier.value;
    _songInfoListener = () {
      if (!mounted) return;
      setState(() {
        _songInfo = _audioPlayerService.songInfoNotifier.value;
      });
    };
    _audioPlayerService.songInfoNotifier.addListener(_songInfoListener!);
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
    _audioPlayerService.updateSpectrumSettings(settings);
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
      _songInfo = songInfo;
    });
  }

  void _toggleSettings() {
    setState(() {
      _isSettingsOpen = !_isSettingsOpen;
    });
  }

  Future<void> _requestAudioPermission() async {
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

  void _closeLibrary() {
    setState(() {
      _isLibraryOpen = false;
    });
  }

  Widget _buildLibraryHandle() {
    return Positioned(
      bottom: 12,
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
      child: LibraryPanel(
        audioPlayerService: _audioPlayerService,
        onClose: _closeLibrary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate panel width based on logic similar to child screens
    final screenWidth = MediaQuery.of(context).size.width;
    // We need to know the effective scale to calculate panel width correctly.
    // However, ScaledLayout handles scaling internally.
    // Let's get the raw scale value for calculation purposes.
    final rawScale = _settingsService.uiScaleNotifier.value;
    final uiScale = rawScale > 0 ? rawScale : 1.0;

    final logicalScreenWidth = screenWidth / uiScale;
    final panelWidth = logicalScreenWidth > 900
        ? logicalScreenWidth / 3
        : (logicalScreenWidth / 2).clamp(300.0, 400.0);

    return ScaledLayout(
      child: GestureDetector(
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
            _buildLibraryHandle(),

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
                onUiScaleChanged: (scale) => _settingsService.saveUiScale(scale),
                fullScreen: _isFullScreen,
                onFullScreenChanged: (val) =>
                    _settingsService.setFullScreen(val, save: true),
                onClose: _toggleSettings,
                hasNotificationAccess: _hasNotificationAccess,
                hasAudioPermission: _hasAudioPermission,
                onRequestNotificationAccess: _openNotificationSettings,
                onRequestAudioPermission: _requestAudioPermission,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_screenConfig.type) {
      case ScreenType.spectrum:
        return SpectrumScreen(
          songInfo: _songInfo,
          spectrumData: _spectrumData,
          settings: _settings,
          config: _screenConfig as SpectrumScreenConfig,
          platformChannels: _platformChannels,
          onToggleSettings: _toggleSettings,
          onPlayPause: _audioPlayerService.playPause,
          onNext: _audioPlayerService.next,
          onPrevious: _audioPlayerService.previous,
        );
      case ScreenType.polo:
        return PoloScreen(
          songInfo: _songInfo,
          config: _screenConfig as PoloScreenConfig,
          platformChannels: _platformChannels,
          onToggleSettings: _toggleSettings,
          settings: _settings,
          debugLayout: _debugLayout,
          onPlayPause: _audioPlayerService.playPause,
          onNext: _audioPlayerService.next,
          onPrevious: _audioPlayerService.previous,
        );
      case ScreenType.dot:
        return DotScreen(
          songInfo: _songInfo,
          spectrumData: _spectrumData,
          settings: _settings,
          config: _screenConfig as DotScreenConfig,
          onToggleSettings: _toggleSettings,
        );
    }
  }
}
