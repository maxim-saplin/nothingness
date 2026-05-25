import 'package:flutter/material.dart';

import 'spectrum_settings.dart';

enum ScreenType { spectrum, polo, dot, void_ }

abstract class ScreenConfig {
  final ScreenType type;
  final String name;

  const ScreenConfig({required this.type, required this.name});

  /// Whether this hero participates in the chrome-owned transport row
  /// contract (B-018).
  ///
  /// Hosted heroes (Spectrum, Dot, Void) opt-in: the Void shell paints
  /// the [TransportRow] at the position dictated by the global
  /// `transport` setting (`top` / `bottom` / `off`) and the hero only
  /// has to lay out content within the *hero band* it is handed.
  ///
  /// Bespoke heroes (Polo) opt-out by overriding to `false`: they paint
  /// their own controls (Polo's LCD-style image overlay) and the shell
  /// stays out of their way regardless of the global transport setting.
  bool get hostsChromeTransport => true;

  /// Whether this hero renders the spectrum visualizer (B-034).
  ///
  /// Default `true` so new heroes opt in by default — the SOUND group's
  /// visualizer-specific rows (`bar count`, `bar style`, `decay speed`,
  /// `visualizer color`) make sense for them. Heroes that don't paint
  /// the visualizer (Dot, Void) override this to `false`; the settings
  /// sheet then hides those rows because tweaking them has no visible
  /// effect on the active screen.
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
  /// Multiplier applied to the title + parent-folder typography (B-035).
  /// Range 0.5..1.5; default 1.0 keeps the existing visual.
  final double textScale;

  const VoidScreenConfig({this.textScale = 1.0})
      : super(type: ScreenType.void_, name: 'Void');

  /// Void renders a typographic hero (track title) only — no spectrum
  /// visualizer (B-034). The SOUND group hides the visualizer-only rows
  /// while this is the active screen.
  @override
  bool get usesVisualizer => false;

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

  VoidScreenConfig copyWith({double? textScale}) {
    return VoidScreenConfig(textScale: textScale ?? this.textScale);
  }
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

  factory SpectrumScreenConfig.fromJson(Map<String, dynamic> json) {
    return SpectrumScreenConfig(
      showMediaControls: json['showMediaControls'] as bool? ?? true,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
      spectrumWidthFactor:
          (json['spectrumWidthFactor'] as num?)?.toDouble() ?? 1.0,
      spectrumHeightFactor:
          (json['spectrumHeightFactor'] as num?)?.toDouble() ?? 1.0,
      mediaControlScale: (json['mediaControlScale'] as num?)?.toDouble() ?? 1.0,
      mediaSliderWidthFactor:
          (json['mediaSliderWidthFactor'] as num?)?.toDouble() ?? 1.0,
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
    double? mediaSliderWidthFactor,
    SpectrumColorScheme? mediaControlColorScheme,
    SpectrumColorScheme? textColorScheme,
  }) {
    return SpectrumScreenConfig(
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
}

class DotScreenConfig extends ScreenConfig {
  final double minDotSize;
  final double maxDotSize;
  final double dotOpacity;
  final double textOpacity;
  final double sensitivity;

  /// Whether the Dot hero overlays the currently-playing track's title and
  /// parent folder above the pulsing dot. Default `false` preserves the
  /// minimalist identity (see B-020); users opt-in from the DISPLAY group
  /// of the settings sheet.
  final bool showSongInfo;

  /// Multiplier applied to the song-info title + parent-folder typography
  /// (B-035). Only meaningful when [showSongInfo] is true.
  /// Range 0.5..1.5; default 1.0 keeps the existing visual.
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

  /// Dot paints a pulsing circle, not a spectrum visualizer (B-034).
  /// SOUND-group visualizer rows are hidden while Dot is the active
  /// screen.
  @override
  bool get usesVisualizer => false;

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

  factory DotScreenConfig.fromJson(Map<String, dynamic> json) {
    return DotScreenConfig(
      minDotSize: (json['minDotSize'] as num?)?.toDouble() ?? 20.0,
      maxDotSize: (json['maxDotSize'] as num?)?.toDouble() ?? 120.0,
      dotOpacity: (json['dotOpacity'] as num?)?.toDouble() ?? 1.0,
      textOpacity: (json['textOpacity'] as num?)?.toDouble() ?? 1.0,
      sensitivity: (json['sensitivity'] as num?)?.toDouble() ?? 1.5,
      showSongInfo: json['showSongInfo'] as bool? ?? false,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
    );
  }

  DotScreenConfig copyWith({
    double? minDotSize,
    double? maxDotSize,
    double? dotOpacity,
    double? textOpacity,
    double? sensitivity,
    bool? showSongInfo,
    double? textScale,
  }) {
    return DotScreenConfig(
      minDotSize: minDotSize ?? this.minDotSize,
      maxDotSize: maxDotSize ?? this.maxDotSize,
      dotOpacity: dotOpacity ?? this.dotOpacity,
      textOpacity: textOpacity ?? this.textOpacity,
      sensitivity: sensitivity ?? this.sensitivity,
      showSongInfo: showSongInfo ?? this.showSongInfo,
      textScale: textScale ?? this.textScale,
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
    this.backgroundImagePath = 'assets/images/polo.webp',
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

  /// Polo is bespoke — it paints its own LCD-style controls as part of
  /// the skin image and opts out of the chrome transport row contract
  /// (B-018).
  @override
  bool get hostsChromeTransport => false;

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
          json['backgroundImagePath'] as String? ?? 'assets/images/polo.webp',
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
