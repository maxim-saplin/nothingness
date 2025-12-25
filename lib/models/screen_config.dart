import 'package:flutter/material.dart';

import 'spectrum_settings.dart';

enum ScreenType { spectrum, polo, dot }

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
        return SpectrumScreenConfig.fromJson(json);
      case ScreenType.polo:
        return PoloScreenConfig.fromJson(json);
      case ScreenType.dot:
        return DotScreenConfig.fromJson(json);
    }
  }
}

class SpectrumScreenConfig extends ScreenConfig {
  final bool showMediaControls;
  final double textScale;
  final double spectrumWidthFactor;
  final double spectrumHeightFactor;
  final double mediaControlScale;
  final SpectrumColorScheme mediaControlColorScheme;
  final SpectrumColorScheme textColorScheme;

  const SpectrumScreenConfig({
    this.showMediaControls = true,
    this.textScale = 0.6,
    this.spectrumWidthFactor = 1.0,
    this.spectrumHeightFactor = 0.5,
    this.mediaControlScale = 0.6,
    this.mediaControlColorScheme = SpectrumColorScheme.cyan,
    this.textColorScheme = SpectrumColorScheme.cyan,
  }) : super(type: ScreenType.spectrum, name: 'Spectrum');

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'showMediaControls': showMediaControls,
    'textScale': textScale,
    'spectrumWidthFactor': spectrumWidthFactor,
    'spectrumHeightFactor': spectrumHeightFactor,
    'mediaControlScale': mediaControlScale,
    'mediaControlColorScheme': mediaControlColorScheme.name,
    'textColorScheme': textColorScheme.name,
  };

  factory SpectrumScreenConfig.fromJson(Map<String, dynamic> json) {
    return SpectrumScreenConfig(
      showMediaControls: json['showMediaControls'] as bool? ?? true,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
      spectrumWidthFactor:
          (json['spectrumWidthFactor'] as num?)?.toDouble() ?? 1.0,
      spectrumHeightFactor:
          (json['spectrumHeightFactor'] as num?)?.toDouble() ?? 1.0,
      mediaControlScale: (json['mediaControlScale'] as num?)?.toDouble() ?? 1.0,
      mediaControlColorScheme: SpectrumColorScheme.values.firstWhere(
        (c) => c.name == (json['mediaControlColorScheme'] as String?),
        orElse: () => SpectrumColorScheme.classic,
      ),
      textColorScheme: SpectrumColorScheme.values.firstWhere(
        (c) => c.name == (json['textColorScheme'] as String?),
        orElse: () => SpectrumColorScheme.classic,
      ),
    );
  }

  SpectrumScreenConfig copyWith({
    bool? showMediaControls,
    double? textScale,
    double? spectrumWidthFactor,
    double? spectrumHeightFactor,
    double? mediaControlScale,
    SpectrumColorScheme? mediaControlColorScheme,
    SpectrumColorScheme? textColorScheme,
  }) {
    return SpectrumScreenConfig(
      showMediaControls: showMediaControls ?? this.showMediaControls,
      textScale: textScale ?? this.textScale,
      spectrumWidthFactor: spectrumWidthFactor ?? this.spectrumWidthFactor,
      spectrumHeightFactor: spectrumHeightFactor ?? this.spectrumHeightFactor,
      mediaControlScale: mediaControlScale ?? this.mediaControlScale,
      mediaControlColorScheme:
          mediaControlColorScheme ?? this.mediaControlColorScheme,
      textColorScheme: textColorScheme ?? this.textColorScheme,
    );
  }
}

class DotScreenConfig extends ScreenConfig {
  final double minDotSize;
  final double maxDotSize;
  final double dotOpacity;
  final double textOpacity;
  final double sensitivity;

  const DotScreenConfig({
    this.minDotSize = 20.0,
    this.maxDotSize = 120.0,
    this.dotOpacity = 1.0,
    this.textOpacity = 1.0,
    this.sensitivity = 1.5,
  }) : super(type: ScreenType.dot, name: 'Dot');

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'minDotSize': minDotSize,
    'maxDotSize': maxDotSize,
    'dotOpacity': dotOpacity,
    'textOpacity': textOpacity,
    'sensitivity': sensitivity,
  };

  factory DotScreenConfig.fromJson(Map<String, dynamic> json) {
    return DotScreenConfig(
      minDotSize: (json['minDotSize'] as num?)?.toDouble() ?? 20.0,
      maxDotSize: (json['maxDotSize'] as num?)?.toDouble() ?? 120.0,
      dotOpacity: (json['dotOpacity'] as num?)?.toDouble() ?? 1.0,
      textOpacity: (json['textOpacity'] as num?)?.toDouble() ?? 1.0,
      sensitivity: (json['sensitivity'] as num?)?.toDouble() ?? 1.5,
    );
  }

  DotScreenConfig copyWith({
    double? minDotSize,
    double? maxDotSize,
    double? dotOpacity,
    double? textOpacity,
    double? sensitivity,
  }) {
    return DotScreenConfig(
      minDotSize: minDotSize ?? this.minDotSize,
      maxDotSize: maxDotSize ?? this.maxDotSize,
      dotOpacity: dotOpacity ?? this.dotOpacity,
      textOpacity: textOpacity ?? this.textOpacity,
      sensitivity: sensitivity ?? this.sensitivity,
    );
  }
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
    this.backgroundImagePath = 'assets/images/polo.heic',
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
          json['backgroundImagePath'] as String? ?? 'assets/images/polo.heic',
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
