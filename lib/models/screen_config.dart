import 'package:flutter/material.dart';

import 'spectrum_settings.dart';

enum ScreenType { spectrum, polo, dot, void_, cassette }

double _d(Object? v, double fallback) => (v as num?)?.toDouble() ?? fallback;

SpectrumColorScheme _scheme(Object? v) => SpectrumColorScheme.values.firstWhere(
      (c) => c.name == (v as String?),
      orElse: () => SpectrumColorScheme.cyan,
    );

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
    final type = ScreenType.values.firstWhere(
      (e) => e.name == json['type'] as String?,
      orElse: () => ScreenType.spectrum,
    );
    return switch (type) {
      ScreenType.spectrum => SpectrumScreenConfig.fromJson(json),
      ScreenType.polo => PoloScreenConfig.fromJson(json),
      ScreenType.dot => DotScreenConfig.fromJson(json),
      ScreenType.void_ => VoidScreenConfig.fromJson(json),
      ScreenType.cassette => CassetteScreenConfig.fromJson(json),
    };
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
  Map<String, dynamic> toJson() =>
      {'type': type.name, 'name': name, 'textScale': textScale};

  factory VoidScreenConfig.fromJson(Map<String, dynamic> json) =>
      VoidScreenConfig(textScale: _d(json['textScale'], 1.0));

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
    this.textScale = 1.0, // B-046: aligned with Void's default.
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
        textScale: _d(json['textScale'], 1.0), // B-046: aligned with Void.
        spectrumWidthFactor: _d(json['spectrumWidthFactor'], 1.0),
        spectrumHeightFactor: _d(json['spectrumHeightFactor'], 0.5),
        mediaControlScale: _d(json['mediaControlScale'], 0.6),
        mediaSliderWidthFactor: _d(json['mediaSliderWidthFactor'], 1.0),
        mediaControlColorScheme: _scheme(json['mediaControlColorScheme']),
        textColorScheme: _scheme(json['textColorScheme']),
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
        minDotSize: _d(json['minDotSize'], 20.0),
        maxDotSize: _d(json['maxDotSize'], 120.0),
        dotOpacity: _d(json['dotOpacity'], 1.0),
        textOpacity: _d(json['textOpacity'], 1.0),
        sensitivity: _d(json['sensitivity'], 1.5),
        showSongInfo: json['showSongInfo'] as bool? ?? false,
        textScale: _d(json['textScale'], 1.0),
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
        // lcdRect is code-driven, not persisted (constructor default is the
        // source of truth so hot-reload tuning works).
        'textColor': textColor.toARGB32(),
      };

  factory PoloScreenConfig.fromJson(Map<String, dynamic> json) =>
      PoloScreenConfig(
        backgroundImagePath:
            json['backgroundImagePath'] as String? ?? 'assets/images/polo.webp',
        fontFamily: json['fontFamily'] as String? ?? 'Press Start 2P',
        textScale: _d(json['textScale'], 1.0),
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

// ---------------------------------------------------------------------------
// Cassette screen
// ---------------------------------------------------------------------------

enum CassetteVariant { v1, v2, v3, v4 }

/// Pure-data metadata for each variant.
const cassetteVariantMeta = <CassetteVariant,
    ({String label, bool hostsOwnTransport, bool usesVisualizer})>{
  CassetteVariant.v1: (label: 'Tape · Mono', hostsOwnTransport: false, usesVisualizer: false),
  CassetteVariant.v2: (label: 'Tape · Amber', hostsOwnTransport: false, usesVisualizer: false),
  CassetteVariant.v3: (label: 'Tape · Colour', hostsOwnTransport: false, usesVisualizer: false),
  CassetteVariant.v4: (label: 'Minimal', hostsOwnTransport: false, usesVisualizer: false),
};

class CassetteScreenConfig extends ScreenConfig {
  final CassetteVariant variant;

  /// Typography multiplier for track info. Range 0.5..1.5.
  final double textScale;

  /// Whether to fire haptic feedback on button taps (mobile only).
  final bool hapticsEnabled;

  const CassetteScreenConfig({
    this.variant = CassetteVariant.v1,
    this.textScale = 1.0,
    this.hapticsEnabled = true,
  }) : super(type: ScreenType.cassette, name: 'Cassette');

  @override
  bool get hostsChromeTransport =>
      !(cassetteVariantMeta[variant]!.hostsOwnTransport);

  @override
  bool get usesVisualizer => cassetteVariantMeta[variant]!.usesVisualizer;

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'name': name,
        'variant': variant.name,
        'textScale': textScale,
        'hapticsEnabled': hapticsEnabled,
      };

  // B-041: fromJson defaults MUST match the const constructor defaults.
  factory CassetteScreenConfig.fromJson(Map<String, dynamic> json) =>
      CassetteScreenConfig(
        variant: CassetteVariant.values.firstWhere(
          (v) => v.name == (json['variant'] as String?),
          orElse: () => CassetteVariant.v1,
        ),
        textScale: _d(json['textScale'], 1.0),
        hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
      );

  CassetteScreenConfig copyWith({
    CassetteVariant? variant,
    double? textScale,
    bool? hapticsEnabled,
  }) =>
      CassetteScreenConfig(
        variant: variant ?? this.variant,
        textScale: textScale ?? this.textScale,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      );
}
