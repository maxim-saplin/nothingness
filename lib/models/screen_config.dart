import 'package:flutter/material.dart';

enum ScreenType { spectrum, polo }

abstract class ScreenConfig {
  final ScreenType type;
  final String name;

  const ScreenConfig({required this.type, required this.name});

  Map<String, dynamic> toJson();

  static ScreenConfig fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    final type = ScreenType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => ScreenType.spectrum,
    );

    switch (type) {
      case ScreenType.spectrum:
        return const SpectrumScreenConfig();
      case ScreenType.polo:
        return PoloScreenConfig.fromJson(json);
    }
  }
}

class SpectrumScreenConfig extends ScreenConfig {
  const SpectrumScreenConfig()
    : super(type: ScreenType.spectrum, name: 'Spectrum');

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'name': name};
}

class PoloScreenConfig extends ScreenConfig {
  final String backgroundImagePath;
  final String fontFamily;
  final Rect lcdRect;
  final Rect playPauseRect;
  final Rect prevRect;
  final Rect nextRect;
  final Color textColor;

  const PoloScreenConfig({
    this.backgroundImagePath = 'assets/images/polo.png',
    this.fontFamily = 'Press Start 2P',
    this.lcdRect = const Rect.fromLTWH(0.31, 0.38, 0.37, 0.14),
    // Initial guesses for controls - adjust in debug mode
    this.playPauseRect = const Rect.fromLTWH(
      0.15,
      0.68,
      0.10,
      0.10,
    ), // Center button
    this.prevRect = const Rect.fromLTWH(0.5, 0.66, 0.11, 0.07), // Left button
    this.nextRect = const Rect.fromLTWH(0.61, 0.66, 0.11, 0.07), // Right button
    this.textColor = const Color(
      0xFF000000,
    ), // Usually LCDs are dark text on light bg or vice versa. Polo image LCD looks bright.
  }) : super(type: ScreenType.polo, name: 'Polo');

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'backgroundImagePath': backgroundImagePath,
    'fontFamily': fontFamily,
    // lcdRect is configuration-driven by code, not persisted
    'textColor': textColor.toARGB32(),
  };

  factory PoloScreenConfig.fromJson(Map<String, dynamic> json) {
    // We intentionally ignore lcdRect from JSON so that the code (constructor default)
    // is always the source of truth. This allows for hot-reload tuning.

    return PoloScreenConfig(
      backgroundImagePath:
          json['backgroundImagePath'] as String? ?? 'assets/images/polo.png',
      fontFamily: json['fontFamily'] as String? ?? 'Press Start 2P',
      // lcdRect uses default from constructor
      textColor: json['textColor'] != null
          ? Color(json['textColor'] as int)
          : const Color(0xFF000000),
    );
  }

  PoloScreenConfig copyWith({
    Rect? lcdRect,
    Rect? playPauseRect,
    Rect? prevRect,
    Rect? nextRect,
    Color? textColor,
  }) {
    return PoloScreenConfig(
      backgroundImagePath: backgroundImagePath,
      fontFamily: fontFamily,
      lcdRect: lcdRect ?? this.lcdRect,
      playPauseRect: playPauseRect ?? this.playPauseRect,
      prevRect: prevRect ?? this.prevRect,
      nextRect: nextRect ?? this.nextRect,
      textColor: textColor ?? this.textColor,
    );
  }
}
