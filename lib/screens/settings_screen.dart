import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/screen_config.dart';
import '../models/spectrum_settings.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final SpectrumSettings settings;
  final ValueChanged<SpectrumSettings> onSettingsChanged;
  final double uiScale;
  final ValueChanged<double> onUiScaleChanged;
  final bool fullScreen;
  final ValueChanged<bool> onFullScreenChanged;
  final VoidCallback onClose;
  final bool hasNotificationAccess;
  final bool hasAudioPermission;
  final VoidCallback onRequestNotificationAccess;
  final VoidCallback onRequestAudioPermission;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.uiScale,
    required this.onUiScaleChanged,
    required this.fullScreen,
    required this.onFullScreenChanged,
    required this.onClose,
    required this.hasNotificationAccess,
    required this.hasAudioPermission,
    required this.onRequestNotificationAccess,
    required this.onRequestAudioPermission,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SpectrumSettings _settings;
  late double _uiScale;
  late bool _fullScreen;
  late ScreenConfig _screenConfig;
  bool _debugLayout = false;
  final _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _uiScale = widget.uiScale;
    _fullScreen = widget.fullScreen;
    _screenConfig = _settingsService.screenConfigNotifier.value;
    _debugLayout = _settingsService.debugLayoutNotifier.value;

    _settingsService.screenConfigNotifier.addListener(
      _onServiceScreenConfigChanged,
    );
    _settingsService.debugLayoutNotifier.addListener(
      _onServiceDebugLayoutChanged,
    );
  }

  @override
  void dispose() {
    _settingsService.screenConfigNotifier.removeListener(
      _onServiceScreenConfigChanged,
    );
    _settingsService.debugLayoutNotifier.removeListener(
      _onServiceDebugLayoutChanged,
    );
    super.dispose();
  }

  void _onServiceScreenConfigChanged() {
    if (mounted) {
      setState(() {
        _screenConfig = _settingsService.screenConfigNotifier.value;
      });
    }
  }

  void _onServiceDebugLayoutChanged() {
    if (mounted) {
      setState(() {
        _debugLayout = _settingsService.debugLayoutNotifier.value;
      });
    }
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _settings = widget.settings;
    }
    if (oldWidget.uiScale != widget.uiScale) {
      _uiScale = widget.uiScale;
    }
    if (oldWidget.fullScreen != widget.fullScreen) {
      _fullScreen = widget.fullScreen;
    }
  }

  void _updateSettings(SpectrumSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    widget.onSettingsChanged(newSettings);
  }

  void _updateUiScale(double newScale) {
    setState(() {
      _uiScale = newScale;
    });
    widget.onUiScaleChanged(newScale);
  }

  void _updateFullScreen(bool enable) {
    setState(() {
      _fullScreen = enable;
    });
    widget.onFullScreenChanged(enable);
  }

  Future<void> _updateScreenType(ScreenType type) async {
    ScreenConfig newConfig;
    if (type == ScreenType.spectrum) {
      newConfig = const SpectrumScreenConfig();
    } else if (type == ScreenType.dot) {
      newConfig = const DotScreenConfig();
    } else {
      newConfig = const PoloScreenConfig(); // Loads default Polo config
    }
    await _settingsService.saveScreenConfig(newConfig);
  }

  Future<void> _updateDotConfig(DotScreenConfig config) async {
    await _settingsService.saveScreenConfig(config);
  }

  Future<void> _updateSpectrumConfig(SpectrumScreenConfig config) async {
    await _settingsService.saveScreenConfig(config);
  }

  void _toggleDebugLayout() {
    _settingsService.toggleDebugLayout();
  }

  @override
  Widget build(BuildContext context) {
    // Frosted glass effect
    return Material(
      color: Colors.transparent,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            color: Colors.black.withAlpha(180), // Semi-transparent black
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 48, 16, 16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withAlpha(25)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),

                // Settings List
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // --- GLOBAL SETTINGS ---
                      _buildSectionHeader('GLOBAL'),
                      const SizedBox(height: 16),

                      // Screen Style Selector
                      _buildOptionTile(
                        title: 'Screen Style',
                        subtitle: _screenConfig.name,
                        child: _buildScreenTypeSelector(),
                      ),
                      const SizedBox(height: 16),

                      // Full Screen Toggle
                      _buildOptionTile(
                        title: 'Full Screen',
                        subtitle: _fullScreen ? 'On' : 'Off',
                        child: SwitchListTile(
                          title: const Text(
                            'Immersive Mode',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          value: _fullScreen,
                          onChanged: _updateFullScreen,
                          activeTrackColor: const Color(0xFF00FF88),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // UI Scale (Global setting)
                      _buildOptionTile(
                        title: 'UI Scale',
                        subtitle: _uiScale < 0
                            ? 'Auto'
                            : '${_uiScale.toStringAsFixed(2)}x',
                        child: _buildUiScaleControl(),
                      ),
                      const SizedBox(height: 24),

                      // Audio Source Selector
                      _buildSectionHeader('AUDIO INPUT'),
                      const SizedBox(height: 16),
                      _buildOptionTile(
                        title: 'Spectrum Source',
                        subtitle: _settings.audioSource.label,
                        child: _buildAudioSourceSelector(),
                      ),
                      const SizedBox(height: 16),
                      if (Platform.isAndroid)
                        _buildOptionTile(
                          title: 'Permissions',
                          subtitle: 'Android only',
                          child: _buildPermissionButtons(),
                        ),
                      const SizedBox(height: 24),

                      // --- SCREEN SPECIFIC SETTINGS ---

                      // 1. SPECTRUM SCREEN SETTINGS
                      if (_screenConfig.type == ScreenType.spectrum) ...[
                        _buildSectionHeader('APPEARANCE'),
                        const SizedBox(height: 16),

                        // Text Color
                        _buildOptionTile(
                          title: 'Text Color',
                          subtitle: (_screenConfig as SpectrumScreenConfig)
                              .textColorScheme
                              .label,
                          child: _buildConfigColorSchemeSelector(
                            currentValue:
                                (_screenConfig as SpectrumScreenConfig)
                                    .textColorScheme,
                            onChanged: (scheme) {
                              _updateSpectrumConfig(
                                (_screenConfig as SpectrumScreenConfig)
                                    .copyWith(textColorScheme: scheme),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Color Scheme
                        _buildOptionTile(
                          title: 'Visualizer Color',
                          subtitle: _settings.colorScheme.label,
                          child: _buildColorSchemeSelector(),
                        ),
                        const SizedBox(height: 16),

                        // Media Controls Color
                        _buildOptionTile(
                          title: 'Media Controls Color',
                          subtitle: (_screenConfig as SpectrumScreenConfig)
                              .mediaControlColorScheme
                              .label,
                          child: _buildConfigColorSchemeSelector(
                            currentValue:
                                (_screenConfig as SpectrumScreenConfig)
                                    .mediaControlColorScheme,
                            onChanged: (scheme) {
                              _updateSpectrumConfig(
                                (_screenConfig as SpectrumScreenConfig)
                                    .copyWith(mediaControlColorScheme: scheme),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildSectionHeader('LAYOUT'),
                        const SizedBox(height: 16),
                        _buildSpectrumLayoutSettings(),
                        const SizedBox(height: 16),

                        _buildSectionHeader('SPECTRUM'),
                        const SizedBox(height: 16),

                        // Bar Count
                        _buildOptionTile(
                          title: 'Number of Bars',
                          subtitle: _settings.barCount.label,
                          child: _buildBarCountSelector(),
                        ),
                        const SizedBox(height: 16),

                        // Bar Style
                        _buildOptionTile(
                          title: 'Bar Style',
                          subtitle: _settings.barStyle.label,
                          child: _buildBarStyleSelector(),
                        ),
                        const SizedBox(height: 24),

                        if (_settings.audioSource == AudioSourceMode.microphone) ...[
                          _buildSectionHeader('AUDIO'),
                          const SizedBox(height: 16),

                          // Noise Gate
                          _buildOptionTile(
                            title: 'Noise Gate',
                            subtitle:
                                '${_settings.noiseGateDb.toStringAsFixed(0)} dB',
                            child: _buildNoiseGateSlider(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Decay Speed
                        _buildOptionTile(
                          title: 'Decay Speed',
                          subtitle: _settings.decaySpeed.label,
                          child: _buildDecaySpeedSelector(),
                        ),
                      ],

                      // 2. POLO SCREEN SETTINGS
                      if (_screenConfig.type == ScreenType.polo) ...[
                        _buildSectionHeader('POLO SETTINGS'),
                        const SizedBox(height: 16),

                        // Debug Layout Toggle (macOS only)
                        if (kDebugMode || (!kIsWeb && Platform.isMacOS))
                          _buildOptionTile(
                            title: 'Debug Layout',
                            subtitle: _debugLayout ? 'On' : 'Off',
                            child: SwitchListTile(
                              title: const Text(
                                'Show LCD Area',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              value: _debugLayout,
                              onChanged: (_) => _toggleDebugLayout(),
                              activeTrackColor: const Color(0xFF00FF88),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],

                      // 3. DOT SCREEN SETTINGS
                      if (_screenConfig.type == ScreenType.dot) ...[
                        _buildSectionHeader('DOT SETTINGS'),
                        const SizedBox(height: 16),
                        _buildDotSettings(),
                      ],

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDotSettings() {
    final config = _screenConfig as DotScreenConfig;
    return Column(
      children: [
        // Sensitivity
        _buildOptionTile(
          title: 'Sensitivity',
          subtitle: '${config.sensitivity.toStringAsFixed(1)}x',
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00FF88),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF00FF88),
              overlayColor: const Color(0xFF00FF88).withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(
              value: config.sensitivity,
              min: 0.5,
              max: 5.0,
              divisions: 45,
              onChanged: (value) {
                _updateDotConfig(config.copyWith(sensitivity: value));
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Max Dot Size
        _buildOptionTile(
          title: 'Max Size',
          subtitle: '${config.maxDotSize.toStringAsFixed(0)} px',
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00FF88),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF00FF88),
              overlayColor: const Color(0xFF00FF88).withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(
              value: config.maxDotSize,
              min: 50.0,
              max: 300.0,
              divisions: 50,
              onChanged: (value) {
                _updateDotConfig(config.copyWith(maxDotSize: value));
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Dot Opacity
        _buildOptionTile(
          title: 'Dot Opacity',
          subtitle: '${(config.dotOpacity * 100).toStringAsFixed(0)}%',
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00FF88),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF00FF88),
              overlayColor: const Color(0xFF00FF88).withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(
              value: config.dotOpacity,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (value) {
                _updateDotConfig(config.copyWith(dotOpacity: value));
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Text Opacity
        _buildOptionTile(
          title: 'Text Opacity',
          subtitle: '${(config.textOpacity * 100).toStringAsFixed(0)}%',
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00FF88),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF00FF88),
              overlayColor: const Color(0xFF00FF88).withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(
              value: config.textOpacity,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (value) {
                _updateDotConfig(config.copyWith(textOpacity: value));
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpectrumLayoutSettings() {
    final config = _screenConfig as SpectrumScreenConfig;
    return Column(
      children: [
        // Text Size Slider
        _buildOptionTile(
          title: 'Text Size',
          subtitle: '${(config.textScale * 100).round()}%',
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00FF88),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF00FF88),
              overlayColor: const Color(0xFF00FF88).withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(
              value: config.textScale,
              min: 0.5,
              max: 1.5,
              divisions: 10,
              onChanged: (val) =>
                  _updateSpectrumConfig(config.copyWith(textScale: val)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Media Controls Toggle
        _buildOptionTile(
          title: 'Media Controls',
          subtitle: config.showMediaControls ? 'On' : 'Off',
          child: SwitchListTile(
            title: const Text(
              'Show Controls',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            value: config.showMediaControls,
            onChanged: (val) =>
                _updateSpectrumConfig(config.copyWith(showMediaControls: val)),
            activeTrackColor: const Color(0xFF00FF88),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 16),

        // Media Controls Size
        if (config.showMediaControls) ...[
          _buildOptionTile(
            title: 'Controls Size',
            subtitle: '${(config.mediaControlScale * 100).round()}%',
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: const Color(0xFF00FF88),
                inactiveTrackColor: Colors.white12,
                thumbColor: const Color(0xFF00FF88),
                overlayColor: const Color(0xFF00FF88).withAlpha(40),
                trackHeight: 4,
              ),
              child: Slider(
                value: config.mediaControlScale,
                min: 0.5,
                max: 1.5,
                divisions: 10,
                onChanged: (val) => _updateSpectrumConfig(
                  config.copyWith(mediaControlScale: val),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Spectrum Width
        _buildOptionTile(
          title: 'Visualizer Width',
          subtitle: '${(config.spectrumWidthFactor * 100).round()}%',
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00FF88),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF00FF88),
              overlayColor: const Color(0xFF00FF88).withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(
              value: config.spectrumWidthFactor,
              min: 0.2,
              max: 1.0,
              divisions: 16,
              onChanged: (val) => _updateSpectrumConfig(
                config.copyWith(spectrumWidthFactor: val),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Spectrum Height
        _buildOptionTile(
          title: 'Visualizer Height',
          subtitle: '${(config.spectrumHeightFactor * 100).round()}%',
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00FF88),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF00FF88),
              overlayColor: const Color(0xFF00FF88).withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(
              value: config.spectrumHeightFactor,
              min: 0.2,
              max: 1.0,
              divisions: 16,
              onChanged: (val) => _updateSpectrumConfig(
                config.copyWith(spectrumHeightFactor: val),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF00FF88),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildAudioSourceSelector() {
    return Row(
      children: AudioSourceMode.values.map((mode) {
        final isSelected = _settings.audioSource == mode;
        return Expanded(
          child: GestureDetector(
            onTap: () => _updateSettings(
              _settings.copyWith(audioSource: mode),
            ),
            child: Container(
              margin: EdgeInsets.only(
                right: mode != AudioSourceMode.values.last ? 8 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00FF88)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF00FF88) : Colors.white24,
                ),
              ),
              child: Text(
                mode.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF0A0A0F) : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPermissionButtons() {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: widget.onRequestAudioPermission,
              icon: const Icon(Icons.mic),
              label: Text(
                widget.hasAudioPermission ? 'Microphone Granted' : 'Enable Mic',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.hasAudioPermission
                    ? Colors.greenAccent.withAlpha(120)
                    : const Color(0xFF00FF88),
                foregroundColor: Colors.black,
              ),
            ),
            ElevatedButton.icon(
              onPressed: widget.onRequestNotificationAccess,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(
                widget.hasNotificationAccess
                    ? 'Notifications Granted'
                    : 'Enable Notifications',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.hasNotificationAccess
                    ? Colors.greenAccent.withAlpha(120)
                    : const Color(0xFF00FF88),
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Permissions are only required on Android.',
          style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A).withAlpha(100),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildScreenTypeSelector() {
    return Row(
      children: ScreenType.values.map((type) {
        final isSelected = _screenConfig.type == type;
        String label;
        switch (type) {
          case ScreenType.spectrum:
            label = 'Spectrum';
            break;
          case ScreenType.polo:
            label = 'Polo';
            break;
          case ScreenType.dot:
            label = 'Dot';
            break;
        }
        return Expanded(
          child: GestureDetector(
            onTap: () => _updateScreenType(type),
            child: Container(
              margin: EdgeInsets.only(
                right: type != ScreenType.values.last ? 8 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00FF88)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF00FF88) : Colors.white24,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF0A0A0F) : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBarCountSelector() {
    return Row(
      children: BarCount.values.map((count) {
        final isSelected = _settings.barCount == count;
        return Expanded(
          child: GestureDetector(
            onTap: () => _updateSettings(_settings.copyWith(barCount: count)),
            child: Container(
              margin: EdgeInsets.only(
                right: count != BarCount.values.last ? 8 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00FF88)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF00FF88) : Colors.white24,
                ),
              ),
              child: Text(
                '${count.count}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF0A0A0F) : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBarStyleSelector() {
    return Row(
      children: BarStyle.values.map((style) {
        final isSelected = _settings.barStyle == style;
        return Expanded(
          child: GestureDetector(
            onTap: () => _updateSettings(_settings.copyWith(barStyle: style)),
            child: Container(
              margin: EdgeInsets.only(
                right: style != BarStyle.values.last ? 8 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00FF88)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF00FF88) : Colors.white24,
                ),
              ),
              child: Text(
                style == BarStyle.segmented
                    ? '80s'
                    : (style == BarStyle.solid ? 'Solid' : 'Glow'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? const Color(0xFF0A0A0F) : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildColorSchemeSelector() {
    return Row(
      children: SpectrumColorScheme.values.map((scheme) {
        final isSelected = _settings.colorScheme == scheme;
        return Expanded(
          child: GestureDetector(
            onTap: () =>
                _updateSettings(_settings.copyWith(colorScheme: scheme)),
            child: Container(
              margin: EdgeInsets.only(
                right: scheme != SpectrumColorScheme.values.last ? 8 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: scheme.colors),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Text(
                scheme.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildConfigColorSchemeSelector({
    required SpectrumColorScheme currentValue,
    required ValueChanged<SpectrumColorScheme> onChanged,
  }) {
    return Row(
      children: SpectrumColorScheme.values.map((scheme) {
        final isSelected = currentValue == scheme;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(scheme),
            child: Container(
              margin: EdgeInsets.only(
                right: scheme != SpectrumColorScheme.values.last ? 8 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: scheme.colors),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Text(
                scheme.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUiScaleControl() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: const Color(0xFF00FF88),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: const Color(0xFF00FF88),
                  overlayColor: const Color(0xFF00FF88).withAlpha(40),
                  trackHeight: 4,
                ),
                child: Slider(
                  // If auto (-1.0), show 1.0 safely (it will be updated shortly by main.dart)
                  // Also guard against any legacy or out-of-range values by clamping.
                  value: _uiScale < 0 ? 1.0 : _uiScale.clamp(0.75, 3.0),
                  min: 0.75,
                  max: 3.0,
                  divisions: 9,
                  onChanged: (value) {
                    _updateUiScale(value);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _updateUiScale(-1.0);
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.white10,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'AUTO',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Small',
              style: TextStyle(
                color: Colors.white.withAlpha(100),
                fontSize: 11,
              ),
            ),
            Text(
              'Default',
              style: TextStyle(
                color: Colors.white.withAlpha(100),
                fontSize: 11,
              ),
            ),
            Text(
              'Huge',
              style: TextStyle(
                color: Colors.white.withAlpha(100),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoiseGateSlider() {
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF00FF88),
            inactiveTrackColor: Colors.white12,
            thumbColor: const Color(0xFF00FF88),
            overlayColor: const Color(0xFF00FF88).withAlpha(40),
            trackHeight: 4,
          ),
          child: Slider(
            value: _settings.noiseGateDb,
            min: -60,
            max: -20,
            divisions: 40,
            onChanged: (value) {
              _updateSettings(_settings.copyWith(noiseGateDb: value));
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'More sensitive',
              style: TextStyle(
                color: Colors.white.withAlpha(100),
                fontSize: 11,
              ),
            ),
            Text(
              'Less sensitive',
              style: TextStyle(
                color: Colors.white.withAlpha(100),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDecaySpeedSelector() {
    return Row(
      children: DecaySpeed.values.map((speed) {
        final isSelected = _settings.decaySpeed == speed;
        return Expanded(
          child: GestureDetector(
            onTap: () => _updateSettings(_settings.copyWith(decaySpeed: speed)),
            child: Container(
              margin: EdgeInsets.only(
                right: speed != DecaySpeed.values.last ? 8 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00FF88)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF00FF88) : Colors.white24,
                ),
              ),
              child: Text(
                speed.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF0A0A0F) : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
