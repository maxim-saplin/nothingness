import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/settings_service.dart';

enum BarCount {
  bars8(8, '8 bars'),
  bars12(12, '12 bars'),
  bars24(24, '24 bars');

  final int count;
  final String label;
  const BarCount(this.count, this.label);
}

enum SpectrumColorScheme {
  classic('Classic', [Color(0xFF00FF88), Color(0xFFFFEB3B), Color(0xFFFF5252)]),
  cyan('Cyan', [Color(0xFF00BCD4), Color(0xFF4DD0E1), Color(0xFF00ACC1)]),
  purple('Purple', [Color(0xFFE040FB), Color(0xFF7C4DFF), Color(0xFFAA00FF)]),
  monochrome('Mono', [Color(0xFF4CAF50), Color(0xFF4CAF50), Color(0xFF4CAF50)]);

  final String label;
  final List<Color> colors;
  const SpectrumColorScheme(this.label, this.colors);
}

enum BarStyle {
  segmented('Segmented (80s)'),
  solid('Solid'),
  glow('Glow');

  final String label;
  const BarStyle(this.label);
}

enum DecaySpeed {
  slow(0.05, 'Slow'),
  medium(0.12, 'Medium'),
  fast(0.25, 'Fast');

  final double value;
  final String label;
  const DecaySpeed(this.value, this.label);
}

enum AudioSourceMode {
  player('Player'),
  microphone('Microphone');

  final String label;
  const AudioSourceMode(this.label);
}

class SpectrumSettings {
  final double noiseGateDb;
  final BarCount barCount;
  final SpectrumColorScheme colorScheme;
  final BarStyle barStyle;
  final DecaySpeed decaySpeed;
  final AudioSourceMode audioSource;

  const SpectrumSettings({
    this.noiseGateDb = SettingsService.defaultNoiseGateDb,
    this.barCount = SettingsService.defaultBarCount,
    this.colorScheme = SettingsService.defaultColorScheme,
    this.barStyle = SettingsService.defaultBarStyle,
    this.decaySpeed = SettingsService.defaultDecaySpeed,
    this.audioSource = SettingsService.defaultAudioSource,
  });

  SpectrumSettings copyWith({
    double? noiseGateDb,
    BarCount? barCount,
    SpectrumColorScheme? colorScheme,
    BarStyle? barStyle,
    DecaySpeed? decaySpeed,
    AudioSourceMode? audioSource,
  }) {
    return SpectrumSettings(
      noiseGateDb: noiseGateDb ?? this.noiseGateDb,
      barCount: barCount ?? this.barCount,
      colorScheme: colorScheme ?? this.colorScheme,
      barStyle: barStyle ?? this.barStyle,
      decaySpeed: decaySpeed ?? this.decaySpeed,
      audioSource: audioSource ?? this.audioSource,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'noiseGateDb': noiseGateDb,
      'barCount': barCount.count,
      'colorScheme': colorScheme.name,
      'barStyle': barStyle.name,
      'decaySpeed': decaySpeed.value,
      'audioSource': audioSource.name,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory SpectrumSettings.fromJson(Map<String, dynamic> json) {
    return SpectrumSettings(
      noiseGateDb:
          (json['noiseGateDb'] as num?)?.toDouble() ??
          SettingsService.defaultNoiseGateDb,
      barCount: BarCount.values.firstWhere(
        (b) => b.count == json['barCount'],
        orElse: () => SettingsService.defaultBarCount,
      ),
      colorScheme: SpectrumColorScheme.values.firstWhere(
        (c) => c.name == json['colorScheme'],
        orElse: () => SettingsService.defaultColorScheme,
      ),
      barStyle: BarStyle.values.firstWhere(
        (s) => s.name == json['barStyle'],
        orElse: () => SettingsService.defaultBarStyle,
      ),
      decaySpeed: DecaySpeed.values.firstWhere(
        (d) => d.value == json['decaySpeed'],
        orElse: () => SettingsService.defaultDecaySpeed,
      ),
      audioSource: AudioSourceMode.values.firstWhere(
        (mode) => mode.name == json['audioSource'],
        orElse: () => SettingsService.defaultAudioSource,
      ),
    );
  }

  factory SpectrumSettings.fromJsonString(String jsonString) {
    try {
      return SpectrumSettings.fromJson(jsonDecode(jsonString));
    } catch (_) {
      return const SpectrumSettings();
    }
  }
}
