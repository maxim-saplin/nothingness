import 'package:flutter/material.dart';

import 'spectrum_settings.dart';

enum ScreenType { spectrum, polo, dot, void_ }

sealed class ScreenConfig {
  final ScreenType type;
  final String name;

  const ScreenConfig({required this.type, required this.name});

  /// Whether this hero participates in the chrome-owned transport row (B-018);
  /// bespoke heroes (Polo) opt out and paint their own controls.
  bool get hostsChromeTransport => true;

  /// Whether this hero renders the spectrum visualizer (B-034); Dot/Void opt out.
  bool get usesVisualizer => true;

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
      case ScreenType.void_:
        return VoidScreenConfig.fromJson(json);
    }
  }
}

class VoidScreenConfig extends ScreenConfig {
  /// Title + parent-folder typography multiplier (B-035). Range 0.5..1.5.
  final double textScale;

  const VoidScreenConfig({this.textScale = 1.0})
      : super(type: ScreenType.void_, name: 'Void');

  @override
  bool get usesVisualizer => false; // B-034: typographic hero, no visualizer

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'textScale': textScale,
  };

  factory VoidScreenConfig.fromJson(Map<String, dynamic> json) =>
      VoidScreenConfig(
        textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
      );

  VoidScreenConfig copyWith({double? textScale}) =>
      VoidScreenConfig(textScale: textScale ?? this.textScale);
}

class SpectrumScreenConfig extends ScreenConfig {
  final bool showMediaControls;
  final double textScale;
  final double spectrumWidthFactor;
  final double spectrumHeightFactor;
  final double mediaControlScale;
  final double mediaSliderWidthFactor;
  final SpectrumColorScheme mediaControlColorScheme;
  final SpectrumColorScheme textColorScheme;

  const SpectrumScreenConfig({
    this.showMediaControls = true,
    this.textScale = 0.6,
    this.spectrumWidthFactor = 1.0,
    this.spectrumHeightFactor = 0.5,
    this.mediaControlScale = 0.6,
    this.mediaSliderWidthFactor = 1.0,
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
    'mediaSliderWidthFactor': mediaSliderWidthFactor,
    'mediaControlColorScheme': mediaControlColorScheme.name,
    'textColorScheme': textColorScheme.name,
  };

  // B-041: fromJson defaults MUST match the const constructor defaults.
  factory SpectrumScreenConfig.fromJson(Map<String, dynamic> json) =>
      SpectrumScreenConfig(
      showMediaControls: json['showMediaControls'] as bool? ?? true,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 0.6,
      spectrumWidthFactor:
          (json['spectrumWidthFactor'] as num?)?.toDouble() ?? 1.0,
      spectrumHeightFactor:
          (json['spectrumHeightFactor'] as num?)?.toDouble() ?? 0.5,
      mediaControlScale: (json['mediaControlScale'] as num?)?.toDouble() ?? 0.6,
      mediaSliderWidthFactor:
          (json['mediaSliderWidthFactor'] as num?)?.toDouble() ?? 1.0,
      mediaControlColorScheme: SpectrumColorScheme.values.firstWhere(
        (c) => c.name == (json['mediaControlColorScheme'] as String?),
        orElse: () => SpectrumColorScheme.cyan,
      ),
      textColorScheme: SpectrumColorScheme.values.firstWhere(
        (c) => c.name == (json['textColorScheme'] as String?),
        orElse: () => SpectrumColorScheme.cyan,
      ),
    );

  SpectrumScreenConfig copyWith({
    bool? showMediaControls,
    double? textScale,
    double? spectrumWidthFactor,
    double? spectrumHeightFactor,
    double? mediaControlScale,
    double? mediaSliderWidthFactor,
    SpectrumColorScheme? mediaControlColorScheme,
    SpectrumColorScheme? textColorScheme,
  }) =>
      SpectrumScreenConfig(
        showMediaControls: showMediaControls ?? this.showMediaControls,
        textScale: textScale ?? this.textScale,
        spectrumWidthFactor: spectrumWidthFactor ?? this.spectrumWidthFactor,
        spectrumHeightFactor: spectrumHeightFactor ?? this.spectrumHeightFactor,
        mediaControlScale: mediaControlScale ?? this.mediaControlScale,
        mediaSliderWidthFactor:
            mediaSliderWidthFactor ?? this.mediaSliderWidthFactor,
        mediaControlColorScheme:
            mediaControlColorScheme ?? this.mediaControlColorScheme,
        textColorScheme: textColorScheme ?? this.textColorScheme,
      );
}

class DotScreenConfig extends ScreenConfig {
  final double minDotSize;
  final double maxDotSize;
  final double dotOpacity;
  final double textOpacity;
  final double sensitivity;

  /// Overlay track title + parent folder above the pulsing dot (B-020); default off.
  final bool showSongInfo;

  /// Song-info typography multiplier (B-035), used only when [showSongInfo]. Range 0.5..1.5.
  final double textScale;

  const DotScreenConfig({
    this.minDotSize = 20.0,
    this.maxDotSize = 120.0,
    this.dotOpacity = 1.0,
    this.textOpacity = 1.0,
    this.sensitivity = 1.5,
    this.showSongInfo = false,
    this.textScale = 1.0,
  }) : super(type: ScreenType.dot, name: 'Dot');

  @override
  bool get usesVisualizer => false; // B-034: pulsing circle, no visualizer

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'minDotSize': minDotSize,
    'maxDotSize': maxDotSize,
    'dotOpacity': dotOpacity,
    'textOpacity': textOpacity,
    'sensitivity': sensitivity,
    'showSongInfo': showSongInfo,
    'textScale': textScale,
  };

  factory DotScreenConfig.fromJson(Map<String, dynamic> json) => DotScreenConfig(
      minDotSize: (json['minDotSize'] as num?)?.toDouble() ?? 20.0,
      maxDotSize: (json['maxDotSize'] as num?)?.toDouble() ?? 120.0,
      dotOpacity: (json['dotOpacity'] as num?)?.toDouble() ?? 1.0,
      textOpacity: (json['textOpacity'] as num?)?.toDouble() ?? 1.0,
      sensitivity: (json['sensitivity'] as num?)?.toDouble() ?? 1.5,
      showSongInfo: json['showSongInfo'] as bool? ?? false,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
    );

  DotScreenConfig copyWith({
    double? minDotSize,
    double? maxDotSize,
    double? dotOpacity,
    double? textOpacity,
    double? sensitivity,
    bool? showSongInfo,
    double? textScale,
  }) =>
      DotScreenConfig(
        minDotSize: minDotSize ?? this.minDotSize,
        maxDotSize: maxDotSize ?? this.maxDotSize,
        dotOpacity: dotOpacity ?? this.dotOpacity,
        textOpacity: textOpacity ?? this.textOpacity,
        sensitivity: sensitivity ?? this.sensitivity,
        showSongInfo: showSongInfo ?? this.showSongInfo,
        textScale: textScale ?? this.textScale,
      );
}

class PoloScreenConfig extends ScreenConfig {
  final String backgroundImagePath;
  final String fontFamily;
  final Rect lcdRect;
  final Rect playPauseRect;
  final Rect prevRect;
  final Rect nextRect;
  final Color textColor;

  /// LCD readout typography multiplier (B-041). Range 0.5..1.5.
  final double textScale;

  // Control rects are initial guesses, adjusted in debug mode.
  const PoloScreenConfig({
    this.backgroundImagePath = 'assets/images/polo.webp',
    this.fontFamily = 'Press Start 2P',
    this.textScale = 1.0,
    this.lcdRect = const Rect.fromLTWH(0.31, 0.38, 0.37, 0.14),
    this.playPauseRect = const Rect.fromLTWH(0.15, 0.68, 0.10, 0.10),
    this.prevRect = const Rect.fromLTWH(0.5, 0.66, 0.11, 0.07),
    this.nextRect = const Rect.fromLTWH(0.61, 0.66, 0.11, 0.07),
    this.textColor = const Color(0xFF000000),
  }) : super(type: ScreenType.polo, name: 'Polo');

  // B-018: Polo paints its own LCD controls; opts out of chrome transport.
  @override
  bool get hostsChromeTransport => false;

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'backgroundImagePath': backgroundImagePath,
    'fontFamily': fontFamily,
    'textScale': textScale,
    // lcdRect is code-driven, not persisted (constructor default is the source
    // of truth so hot-reload tuning works).
    'textColor': textColor.toARGB32(),
  };

  factory PoloScreenConfig.fromJson(Map<String, dynamic> json) =>
      PoloScreenConfig(
        backgroundImagePath: json['backgroundImagePath'] as String? ??
            'assets/images/polo.webp',
        fontFamily: json['fontFamily'] as String? ?? 'Press Start 2P',
        textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
        textColor: json['textColor'] != null
            ? Color(json['textColor'] as int)
            : const Color(0xFF000000),
      );

  PoloScreenConfig copyWith({
    Rect? lcdRect,
    Rect? playPauseRect,
    Rect? prevRect,
    Rect? nextRect,
    Color? textColor,
    double? textScale,
  }) =>
      PoloScreenConfig(
        backgroundImagePath: backgroundImagePath,
        fontFamily: fontFamily,
        textScale: textScale ?? this.textScale,
        lcdRect: lcdRect ?? this.lcdRect,
        playPauseRect: playPauseRect ?? this.playPauseRect,
        prevRect: prevRect ?? this.prevRect,
        nextRect: nextRect ?? this.nextRect,
        textColor: textColor ?? this.textColor,
      );
}
