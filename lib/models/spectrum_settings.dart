import 'dart:convert';

import 'package:flutter/material.dart';

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

class SpectrumSettings {
  final double noiseGateDb;
  final BarCount barCount;
  final SpectrumColorScheme colorScheme;
  final BarStyle barStyle;
  final DecaySpeed decaySpeed;

  const SpectrumSettings({
    this.noiseGateDb = -35.0,
    this.barCount = BarCount.bars12,
    this.colorScheme = SpectrumColorScheme.classic,
    this.barStyle = BarStyle.segmented,
    this.decaySpeed = DecaySpeed.medium,
  });

  SpectrumSettings copyWith({
    double? noiseGateDb,
    BarCount? barCount,
    SpectrumColorScheme? colorScheme,
    BarStyle? barStyle,
    DecaySpeed? decaySpeed,
  }) {
    return SpectrumSettings(
      noiseGateDb: noiseGateDb ?? this.noiseGateDb,
      barCount: barCount ?? this.barCount,
      colorScheme: colorScheme ?? this.colorScheme,
      barStyle: barStyle ?? this.barStyle,
      decaySpeed: decaySpeed ?? this.decaySpeed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'noiseGateDb': noiseGateDb,
      'barCount': barCount.count,
      'colorScheme': colorScheme.name,
      'barStyle': barStyle.name,
      'decaySpeed': decaySpeed.value,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory SpectrumSettings.fromJson(Map<String, dynamic> json) {
    return SpectrumSettings(
      noiseGateDb: (json['noiseGateDb'] as num?)?.toDouble() ?? -35.0,
      barCount: BarCount.values.firstWhere(
        (b) => b.count == json['barCount'],
        orElse: () => BarCount.bars12,
      ),
      colorScheme: SpectrumColorScheme.values.firstWhere(
        (c) => c.name == json['colorScheme'],
        orElse: () => SpectrumColorScheme.classic,
      ),
      barStyle: BarStyle.values.firstWhere(
        (s) => s.name == json['barStyle'],
        orElse: () => BarStyle.segmented,
      ),
      decaySpeed: DecaySpeed.values.firstWhere(
        (d) => d.value == json['decaySpeed'],
        orElse: () => DecaySpeed.medium,
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

