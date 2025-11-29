import 'package:flutter/material.dart';

import '../models/spectrum_settings.dart';

class SettingsScreen extends StatefulWidget {
  final SpectrumSettings settings;
  final ValueChanged<SpectrumSettings> onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SpectrumSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _updateSettings(SpectrumSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
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
            title: 'Noise Gate Sensitivity',
            subtitle: '${_settings.noiseGateDb.toStringAsFixed(0)} dB',
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

          // Preview
          _buildPreviewSection(),
        ],
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
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                ),
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
              margin: EdgeInsets.only(right: count != BarCount.values.last ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF00FF88) : Colors.transparent,
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
              margin: EdgeInsets.only(right: style != BarStyle.values.last ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF00FF88) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF00FF88) : Colors.white24,
                ),
              ),
              child: Text(
                style == BarStyle.segmented ? '80s' : (style == BarStyle.solid ? 'Solid' : 'Glow'),
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
            onTap: () => _updateSettings(_settings.copyWith(colorScheme: scheme)),
            child: Container(
              margin: EdgeInsets.only(right: scheme != SpectrumColorScheme.values.last ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: scheme.colors,
                ),
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
                  color: scheme == SpectrumColorScheme.monochrome ? Colors.white : Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
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
              style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 11),
            ),
            Text(
              'Less sensitive',
              style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 11),
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
              margin: EdgeInsets.only(right: speed != DecaySpeed.values.last ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF00FF88) : Colors.transparent,
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

  Widget _buildPreviewSection() {
    // Simple preview bars showing the selected style
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: _buildPreviewBars(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBars() {
    // Static demo values
    final demoValues = [0.3, 0.5, 0.8, 0.6, 0.9, 0.4, 0.7, 0.5];
    final barCount = _settings.barCount.count;
    final colors = _settings.colorScheme.colors;

    // Resample demo values to match bar count
    final values = List.generate(barCount, (i) {
      final idx = (i * demoValues.length / barCount).floor() % demoValues.length;
      return demoValues[idx];
    });

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(barCount, (i) {
        final height = values[i] * 80;
        final normalizedHeight = values[i];

        Color color;
        if (normalizedHeight < 0.5) {
          color = Color.lerp(colors[0], colors[1], normalizedHeight * 2)!;
        } else {
          color = Color.lerp(colors[1], colors[2], (normalizedHeight - 0.5) * 2)!;
        }

        return Container(
          width: barCount <= 12 ? 14 : 8,
          height: height,
          margin: EdgeInsets.symmetric(horizontal: barCount <= 12 ? 2 : 1),
          decoration: BoxDecoration(
            color: color,
            borderRadius: _settings.barStyle == BarStyle.glow
                ? BorderRadius.circular(2)
                : BorderRadius.zero,
            boxShadow: _settings.barStyle == BarStyle.glow
                ? [BoxShadow(color: color.withAlpha(100), blurRadius: 8)]
                : null,
          ),
        );
      }),
    );
  }
}

