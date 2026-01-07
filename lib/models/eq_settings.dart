import 'dart:convert';

import '../services/settings_service.dart';

/// Global EQ settings (Android-only effect in v1; persisted cross-platform).
class EqSettings {
  static const int bandCount = 5;

  /// Fixed UI band centers in Hz (for display and device-band mapping on Android).
  static const List<int> uiBandCentersHz = <int>[60, 230, 910, 3600, 14000];

  final bool enabled;

  /// Gain per UI band in dB. Must be length [bandCount].
  final List<double> gainsDb;

  const EqSettings({
    this.enabled = SettingsService.defaultEqEnabled,
    List<double>? gainsDb,
  }) : gainsDb =
            gainsDb ?? const <double>[0.0, 0.0, 0.0, 0.0, 0.0];

  EqSettings copyWith({bool? enabled, List<double>? gainsDb}) {
    return EqSettings(
      enabled: enabled ?? this.enabled,
      gainsDb: gainsDb ?? this.gainsDb,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'gainsDb': gainsDb,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory EqSettings.fromJson(Map<String, dynamic> json) {
    final enabled = (json['enabled'] as bool?) ?? SettingsService.defaultEqEnabled;
    final raw = json['gainsDb'];
    List<double> gains;
    if (raw is List) {
      gains = raw.map((e) => (e as num).toDouble()).toList(growable: false);
    } else {
      gains = const <double>[0.0, 0.0, 0.0, 0.0, 0.0];
    }

    // Normalize to exact bandCount.
    if (gains.length != bandCount) {
      final normalized = List<double>.filled(bandCount, 0.0);
      for (var i = 0; i < bandCount && i < gains.length; i++) {
        normalized[i] = gains[i];
      }
      gains = normalized;
    }

    return EqSettings(enabled: enabled, gainsDb: gains);
  }

  factory EqSettings.fromJsonString(String jsonString) {
    try {
      return EqSettings.fromJson(jsonDecode(jsonString));
    } catch (_) {
      return const EqSettings();
    }
  }
}



