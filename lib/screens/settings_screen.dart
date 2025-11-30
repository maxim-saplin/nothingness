import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/spectrum_settings.dart';

class SettingsScreen extends StatefulWidget {
  final SpectrumSettings settings;
  final ValueChanged<SpectrumSettings> onSettingsChanged;
  final double uiScale;
  final ValueChanged<double> onUiScaleChanged;
  final VoidCallback onClose;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.uiScale,
    required this.onUiScaleChanged,
    required this.onClose,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SpectrumSettings _settings;
  late double _uiScale;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _uiScale = widget.uiScale;
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
                      const SizedBox(height: 16),

                      _buildSectionHeader('DISPLAY'),
                      const SizedBox(height: 16),

                      // UI Scale
                      _buildOptionTile(
                        title: 'UI Scale',
                        subtitle: _uiScale < 0
                            ? 'Auto'
                            : '${_uiScale.toStringAsFixed(2)}x',
                        child: _buildUiScaleControl(),
                      ),
                      const SizedBox(height: 16),

                      // Color Scheme
                      _buildOptionTile(
                        title: 'Color Scheme',
                        subtitle: _settings.colorScheme.label,
                        child: _buildColorSchemeSelector(),
                      ),
                      const SizedBox(height: 24),

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

                      // Decay Speed
                      _buildOptionTile(
                        title: 'Decay Speed',
                        subtitle: _settings.decaySpeed.label,
                        child: _buildDecaySpeedSelector(),
                      ),
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
                  color: scheme == SpectrumColorScheme.monochrome
                      ? Colors.white
                      : Colors.white,
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
