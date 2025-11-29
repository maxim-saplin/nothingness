import 'dart:async';

import 'package:flutter/material.dart';

import '../models/song_info.dart';
import '../models/spectrum_settings.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../widgets/media_button.dart';
import '../widgets/song_info_display.dart';
import '../widgets/spectrum_visualizer.dart';
import 'settings_screen.dart';

class MediaControllerPage extends StatefulWidget {
  const MediaControllerPage({super.key});

  @override
  State<MediaControllerPage> createState() => _MediaControllerPageState();
}

class _MediaControllerPageState extends State<MediaControllerPage>
    with WidgetsBindingObserver {
  final _platformChannels = PlatformChannels();

  SongInfo? _songInfo;
  List<double> _spectrumData = List.filled(32, 0.0);
  StreamSubscription<List<double>>? _spectrumSubscription;
  Timer? _songInfoTimer;

  bool _hasNotificationAccess = false;
  bool _hasAudioPermission = false;

  SpectrumSettings _settings = const SpectrumSettings();
  bool _isSettingsOpen = false;

  final _settingsService = SettingsService();

  Color get _accentColor => _settings.colorScheme.colors.first;
  Color get _accentColorSoft => _settings.colorScheme.colors.length > 1
      ? _settings.colorScheme.colors[1]
      : _settings.colorScheme.colors.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadSettings();

    if (PlatformChannels.isAndroid) {
      _checkPermissions();
      _startSongInfoPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    setState(() {
      _settings = settings;
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
    final notificationAccess = await _platformChannels
        .isNotificationAccessGranted();
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
    // Determine panel width logic
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth > 900
        ? screenWidth / 3
        : (screenWidth / 2).clamp(300.0, 400.0);

    return Stack(
      children: [
        // Main Content
        Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.more_vert, color: _accentColor),
                onPressed: _toggleSettings,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Song info section
                SongInfoDisplay(
                  songInfo: _songInfo,
                  hasNotificationAccess: _hasNotificationAccess,
                  isAndroid: PlatformChannels.isAndroid,
                ),
                const SizedBox(height: 40),
                // Spectrum visualizer
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SpectrumVisualizer(
                      data: _spectrumData,
                      settings: _settings,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // Media controls
                _buildMediaControls(),
                const SizedBox(height: 20),
                // Permission buttons (if needed)
                if (PlatformChannels.isAndroid) _buildPermissionButtons(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),

        // Settings Panel
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
            onClose: _toggleSettings,
          ),
        ),
      ],
    );
  }

  Widget _buildMediaControls() {
    final isPlaying = _songInfo?.isPlaying ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous button
        MediaButton(
          icon: Icons.skip_previous_rounded,
          size: 48,
          accentColor: _accentColorSoft,
          inactiveBackgroundColor: Colors.white.withAlpha(10),
          inactiveIconColor: Colors.white70,
          onTap: _platformChannels.previous,
        ),
        const SizedBox(width: 32),
        // Play/Pause button
        MediaButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 72,
          isPrimary: true,
          accentColor: _accentColor,
          onTap: _platformChannels.playPause,
        ),
        const SizedBox(width: 32),
        // Next button
        MediaButton(
          icon: Icons.skip_next_rounded,
          size: 48,
          accentColor: _accentColorSoft,
          inactiveBackgroundColor: Colors.white.withAlpha(10),
          inactiveIconColor: Colors.white70,
          onTap: _platformChannels.next,
        ),
      ],
    );
  }

  Widget _buildPermissionButtons() {
    final buttons = <Widget>[];

    if (!_hasNotificationAccess) {
      buttons.add(
        TextButton.icon(
          onPressed: _platformChannels.openNotificationSettings,
          icon: const Icon(Icons.settings, size: 18),
          label: const Text('Enable Notification Access'),
          style: TextButton.styleFrom(foregroundColor: _accentColor),
        ),
      );
    }

    if (!_hasAudioPermission) {
      buttons.add(
        TextButton.icon(
          onPressed: _platformChannels.requestAudioPermission,
          icon: const Icon(Icons.mic, size: 18),
          label: const Text('Enable Microphone'),
          style: TextButton.styleFrom(foregroundColor: _accentColorSoft),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: buttons,
      ),
    );
  }
}
