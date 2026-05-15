import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/operating_mode.dart';
import '../models/screen_config.dart';
import '../models/spectrum_settings.dart';
import '../models/theme_id.dart';
import '../models/theme_variant.dart';
import '../models/transport_position.dart';
import '../screens/help_screen.dart';
import '../screens/log_screen.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../theme/app_geometry.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';

/// Themed settings surface for the Void chrome.
///
/// This is the single settings UI for the app — there is no legacy
/// `SettingsScreen` route any more. Groups (MODE / LOOK / SOUND /
/// LIBRARY / EXTERNAL / DISPLAY / ABOUT) adapt to the active operating
/// mode and the active home-screen (visualisation) so per-visualisation
/// knobs only appear when they're relevant.
///
/// Three row primitives:
///   * [_row]: cycle row — label, current value, tap to cycle.
///   * [_sliderRow]: label + current value, slider below.
///   * [_toggleRow]: label, on/off state, tap to flip.
class VoidSettingsSheet extends StatefulWidget {
  const VoidSettingsSheet({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VoidSettingsSheet()),
    );
  }

  @override
  State<VoidSettingsSheet> createState() => _VoidSettingsSheetState();
}

class _VoidSettingsSheetState extends State<VoidSettingsSheet> {
  final SettingsService _settings = SettingsService();

  bool _hasAudio = false;
  bool _hasNotification = false;
  String _versionLabel = '...';

  // Notifiers the sheet renders against. Subscribing here lets every row pick
  // up cycle / slider mutations without each individual cycle handler having
  // to remember `setState` — earlier handlers had inconsistent calls and the
  // value column drifted out of sync with what was actually persisted.
  late final List<Listenable> _watched = <Listenable>[
    _settings.operatingModeNotifier,
    _settings.themeIdNotifier,
    _settings.themeVariantNotifier,
    _settings.screenConfigNotifier,
    _settings.immersiveNotifier,
    _settings.transportPositionNotifier,
    _settings.fullScreenNotifier,
    _settings.uiScaleNotifier,
    _settings.settingsNotifier,
    _settings.useFilenameForMetadataNotifier,
    _settings.smartFoldersPresentationNotifier,
    _settings.debugLayoutNotifier,
    _settings.audioDiagnosticsOverlayNotifier,
    _settings.eqSettingsNotifier,
  ];

  void _onAnySettingChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    for (final l in _watched) {
      l.addListener(_onAnySettingChanged);
    }
    _refreshPermissions();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionLabel = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      // Non-fatal — keep the placeholder.
    }
  }

  @override
  void dispose() {
    for (final l in _watched) {
      l.removeListener(_onAnySettingChanged);
    }
    super.dispose();
  }

  Future<void> _refreshPermissions() async {
    if (!PlatformChannels.isAndroid) return;
    final p = PlatformChannels();
    final notif = await p.isNotificationAccessGranted();
    final audio = await p.hasAudioPermission();
    if (!mounted) return;
    setState(() {
      _hasNotification = notif;
      _hasAudio = audio;
    });
  }

  // ---------------------------------------------------------------------------
  // Cycle helpers (enum-valued rows)
  // ---------------------------------------------------------------------------

  void _cycleMode() {
    final values = OperatingMode.values;
    final cur = _settings.operatingModeNotifier.value;
    _settings.saveOperatingMode(values[(values.indexOf(cur) + 1) % values.length]);
  }

  void _cycleTheme() {
    final values = ThemeId.values;
    final cur = _settings.themeIdNotifier.value;
    _settings.saveThemeId(values[(values.indexOf(cur) + 1) % values.length]);
    setState(() {});
  }

  void _cycleVariant() {
    const order = <ThemeVariant>[
      ThemeVariant.dark,
      ThemeVariant.light,
      ThemeVariant.system,
    ];
    final cur = _settings.themeVariantNotifier.value;
    _settings.saveThemeVariant(order[(order.indexOf(cur) + 1) % order.length]);
  }

  void _cycleScreen() {
    final cur = _settings.screenConfigNotifier.value.type;
    const order = <ScreenType>[
      ScreenType.spectrum,
      ScreenType.polo,
      ScreenType.dot,
      ScreenType.void_,
    ];
    final next = order[(order.indexOf(cur) + 1) % order.length];
    final ScreenConfig nextConfig;
    switch (next) {
      case ScreenType.spectrum:
        nextConfig = const SpectrumScreenConfig();
      case ScreenType.polo:
        nextConfig = const PoloScreenConfig();
      case ScreenType.dot:
        nextConfig = const DotScreenConfig();
      case ScreenType.void_:
        nextConfig = const VoidScreenConfig();
    }
    _settings.saveScreenConfig(nextConfig);
  }

  void _cycleBarCount() {
    final cur = _settings.settingsNotifier.value;
    final values = BarCount.values;
    final next = values[(values.indexOf(cur.barCount) + 1) % values.length];
    _settings.saveSettings(cur.copyWith(barCount: next));
    setState(() {});
  }

  void _cycleBarStyle() {
    final cur = _settings.settingsNotifier.value;
    final values = BarStyle.values;
    final next = values[(values.indexOf(cur.barStyle) + 1) % values.length];
    _settings.saveSettings(cur.copyWith(barStyle: next));
    setState(() {});
  }

  void _cycleDecaySpeed() {
    final cur = _settings.settingsNotifier.value;
    final values = DecaySpeed.values;
    final next = values[(values.indexOf(cur.decaySpeed) + 1) % values.length];
    _settings.saveSettings(cur.copyWith(decaySpeed: next));
    setState(() {});
  }

  void _cycleTransportPosition() {
    final values = TransportPosition.values;
    final cur = _settings.transportPositionNotifier.value;
    final next = values[(values.indexOf(cur) + 1) % values.length];
    _settings.setTransportPosition(next);
  }

  void _cycleVisualizerColor() {
    final cur = _settings.settingsNotifier.value;
    final values = SpectrumColorScheme.values;
    final next = values[(values.indexOf(cur.colorScheme) + 1) % values.length];
    _settings.saveSettings(cur.copyWith(colorScheme: next));
    setState(() {});
  }

  void _cycleSpectrumTextColor() {
    final cfg = _settings.screenConfigNotifier.value;
    if (cfg is! SpectrumScreenConfig) return;
    final values = SpectrumColorScheme.values;
    final next = values[(values.indexOf(cfg.textColorScheme) + 1) % values.length];
    _settings.saveScreenConfig(cfg.copyWith(textColorScheme: next));
    setState(() {});
  }

  void _cycleSpectrumMediaColor() {
    final cfg = _settings.screenConfigNotifier.value;
    if (cfg is! SpectrumScreenConfig) return;
    final values = SpectrumColorScheme.values;
    final next = values[
        (values.indexOf(cfg.mediaControlColorScheme) + 1) % values.length];
    _settings.saveScreenConfig(cfg.copyWith(mediaControlColorScheme: next));
    setState(() {});
  }

  String _uiScaleLabel() {
    final v = _settings.uiScaleNotifier.value;
    if (v < 0) return 'auto';
    return '${v.toStringAsFixed(2)}x';
  }

  String _labelFor(ScreenType type) {
    switch (type) {
      case ScreenType.spectrum:
        return 'spectrum';
      case ScreenType.polo:
        return 'polo';
      case ScreenType.dot:
        return 'dot';
      case ScreenType.void_:
        return 'void';
    }
  }

  Future<void> _openNotificationSettings() async {
    await PlatformChannels().openNotificationSettings();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshPermissions();
  }

  Future<void> _requestMicPermission() async {
    await Permission.microphone.request();
    await _refreshPermissions();
  }

  Future<void> _openLogs(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LogScreen()));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final geometry = Theme.of(context).extension<AppGeometry>()!;

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ValueListenableBuilder<OperatingMode>(
          valueListenable: _settings.operatingModeNotifier,
          builder: (context, mode, _) {
            return ListView(
              padding: EdgeInsets.zero,
              children: _buildGroups(
                mode: mode,
                palette: palette,
                typography: typography,
                geometry: geometry,
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildGroups({
    required OperatingMode mode,
    required AppPalette palette,
    required AppTypography typography,
    required AppGeometry geometry,
  }) {
    final isOwn = mode == OperatingMode.own;
    final isBackground = mode == OperatingMode.background;
    final type = _settings.screenConfigNotifier.value.type;
    final spectrumCfg = _settings.screenConfigNotifier.value is SpectrumScreenConfig
        ? _settings.screenConfigNotifier.value as SpectrumScreenConfig
        : null;
    final dotCfg = _settings.screenConfigNotifier.value is DotScreenConfig
        ? _settings.screenConfigNotifier.value as DotScreenConfig
        : null;
    final spectrum = _settings.settingsNotifier.value;

    return [
      _header(palette, typography),

      // ------------------------------------------------------------------- MODE
      _groupHeader('MODE', palette, typography),
      _row(
        key: const ValueKey('void-settings-mode'),
        label: 'operating mode',
        value: mode.name,
        onTap: _cycleMode,
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),

      // ------------------------------------------------------------------- LOOK
      _groupHeader('LOOK', palette, typography),
      _row(
        key: const ValueKey('void-settings-theme'),
        label: 'theme',
        value: _settings.themeIdNotifier.value.storageKey,
        onTap: _cycleTheme,
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _row(
        key: const ValueKey('void-settings-variant'),
        label: 'variant',
        value: _settings.themeVariantNotifier.value.name,
        onTap: _cycleVariant,
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _row(
        key: const ValueKey('void-settings-screen'),
        label: 'screen',
        value: _labelFor(type),
        onTap: _cycleScreen,
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      // Void-chrome immersive: replaces the previous drag-down gesture.
      _toggleRow(
        key: const ValueKey('void-settings-immersive'),
        label: 'immersive',
        value: _settings.immersiveNotifier.value,
        onToggle: () {
          _settings.setImmersive(!_settings.immersiveNotifier.value);
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      // Transport strip — cycle row over bottom / top / off. `top` pins the
      // strip immediately below the hero so it stays at a fixed y as the
      // user scrolls a long folder; `bottom` keeps the original placement
      // above the crumb; `off` hides the strip altogether (hero gestures
      // and the bottom progress hairline still work).
      _row(
        key: const ValueKey('void-settings-transport'),
        label: 'transport',
        value: _settings.transportPositionNotifier.value.label,
        onTap: _cycleTransportPosition,
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _toggleRow(
        key: const ValueKey('void-settings-full-screen'),
        label: 'full screen',
        value: _settings.fullScreenNotifier.value,
        onToggle: () {
          _settings.setFullScreen(
            !_settings.fullScreenNotifier.value,
            save: true,
          );
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _sliderRow(
        key: const ValueKey('void-settings-ui-scale'),
        label: 'ui scale',
        valueText: _uiScaleLabel(),
        min: 0.75,
        max: 3.0,
        divisions: 9,
        currentValue: _settings.uiScaleNotifier.value < 0
            ? _effectiveAutoUiScale()
            : _settings.uiScaleNotifier.value.clamp(0.75, 3.0),
        trailing: _autoChip(
          isAuto: _settings.uiScaleNotifier.value < 0,
          palette: palette,
          typography: typography,
        ),
        onChanged: (v) {
          _settings.saveUiScale(v);
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),

      // ------------------------------------------------------------------ SOUND
      if (isOwn) ...[
        _groupHeader('SOUND', palette, typography),
        _row(
          key: const ValueKey('void-settings-bar-count'),
          label: 'bar count',
          value: '${spectrum.barCount.count}',
          onTap: _cycleBarCount,
          palette: palette,
          typography: typography,
          geometry: geometry,
        ),
        _row(
          key: const ValueKey('void-settings-bar-style'),
          label: 'bar style',
          value: spectrum.barStyle.name,
          onTap: _cycleBarStyle,
          palette: palette,
          typography: typography,
          geometry: geometry,
        ),
        _row(
          key: const ValueKey('void-settings-decay-speed'),
          label: 'decay speed',
          value: spectrum.decaySpeed.name,
          onTap: _cycleDecaySpeed,
          palette: palette,
          typography: typography,
          geometry: geometry,
        ),
        _row(
          key: const ValueKey('void-settings-visualizer-color'),
          label: 'visualizer color',
          value: spectrum.colorScheme.label,
          onTap: _cycleVisualizerColor,
          palette: palette,
          typography: typography,
          geometry: geometry,
        ),
        _row(
          key: const ValueKey('void-settings-eq'),
          label: 'eq',
          value: 'unavailable',
          onTap: () {},
          palette: palette,
          typography: typography,
          geometry: geometry,
          enabled: false,
        ),

        _groupHeader('LIBRARY', palette, typography),
        _toggleRow(
          key: const ValueKey('void-settings-scan-on-startup'),
          label: 'filename fallback',
          value: _settings.useFilenameForMetadataNotifier.value,
          onToggle: () {
            _settings.setUseFilenameForMetadata(
              !_settings.useFilenameForMetadataNotifier.value,
            );
            setState(() {});
          },
          palette: palette,
          typography: typography,
          geometry: geometry,
        ),
        _toggleRow(
          key: const ValueKey('void-settings-smart-folders'),
          label: 'smart folders',
          value: _settings.smartFoldersPresentationNotifier.value,
          onToggle: () {
            _settings.setSmartFoldersPresentation(
              !_settings.smartFoldersPresentationNotifier.value,
            );
            setState(() {});
          },
          palette: palette,
          typography: typography,
          geometry: geometry,
        ),
      ],

      // --------------------------------------------------------------- EXTERNAL
      if (isBackground) ...[
        _groupHeader('EXTERNAL', palette, typography),
        if (Platform.isAndroid)
          _row(
            key: const ValueKey('void-settings-notification-listener'),
            label: 'notification listener',
            value: _hasNotification ? 'granted' : 'open settings',
            onTap: _openNotificationSettings,
            palette: palette,
            typography: typography,
            geometry: geometry,
          ),
        if (Platform.isAndroid)
          _row(
            key: const ValueKey('void-settings-mic-permission'),
            label: 'mic permission',
            value: _hasAudio ? 'granted' : 'request',
            onTap: _requestMicPermission,
            palette: palette,
            typography: typography,
            geometry: geometry,
          ),
        _sliderRow(
          key: const ValueKey('void-settings-noise-gate'),
          label: 'noise gate',
          valueText: '${spectrum.noiseGateDb.toStringAsFixed(0)} dB',
          min: -60,
          max: -20,
          divisions: 40,
          currentValue: spectrum.noiseGateDb,
          onChanged: (v) {
            _settings.saveSettings(spectrum.copyWith(noiseGateDb: v));
            setState(() {});
          },
          palette: palette,
          typography: typography,
          geometry: geometry,
        ),
      ],

      // ---------------------------------------------------------------- DISPLAY
      _groupHeader('DISPLAY', palette, typography),
      if (kDebugMode || (!kIsWeb && Platform.isMacOS))
        _toggleRow(
          key: const ValueKey('void-settings-debug-layout'),
          label: 'debug layout',
          value: _settings.debugLayoutNotifier.value,
          onToggle: () {
            _settings.toggleDebugLayout();
            setState(() {});
          },
          palette: palette,
          typography: typography,
          geometry: geometry,
        ),
      if (type == ScreenType.spectrum && spectrumCfg != null)
        ..._buildSpectrumDisplayRows(spectrumCfg, palette, typography, geometry),
      if (type == ScreenType.dot && dotCfg != null)
        ..._buildDotDisplayRows(dotCfg, palette, typography, geometry),
      if (type == ScreenType.polo)
        _row(
          key: const ValueKey('void-settings-polo-display'),
          label: 'polo',
          value: 'no options',
          onTap: () {},
          palette: palette,
          typography: typography,
          geometry: geometry,
          enabled: false,
        ),
      if (type == ScreenType.void_)
        _row(
          key: const ValueKey('void-settings-void-display'),
          label: 'void',
          value: 'no options',
          onTap: () {},
          palette: palette,
          typography: typography,
          geometry: geometry,
          enabled: false,
        ),

      // ----------------------------------------------------------------- ABOUT
      _groupHeader('ABOUT', palette, typography),
      _row(
        key: const ValueKey('void-settings-help'),
        label: 'help',
        value: '>',
        onTap: () => HelpScreen.push(context),
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _row(
        key: const ValueKey('void-settings-logs'),
        label: 'logs',
        value: '>',
        onTap: () => _openLogs(context),
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _toggleRow(
        key: const ValueKey('void-settings-audio-diagnostics'),
        label: 'audio diagnostics',
        value: _settings.audioDiagnosticsOverlayNotifier.value,
        onToggle: () {
          _settings.setAudioDiagnosticsOverlay(
            !_settings.audioDiagnosticsOverlayNotifier.value,
          );
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _row(
        key: const ValueKey('void-settings-version'),
        label: 'version',
        value: _versionLabel,
        onTap: () {},
        palette: palette,
        typography: typography,
        geometry: geometry,
        enabled: false,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Screen-specific display rows
  // ---------------------------------------------------------------------------

  List<Widget> _buildSpectrumDisplayRows(
    SpectrumScreenConfig cfg,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    return [
      _row(
        key: const ValueKey('void-settings-spectrum-text-color'),
        label: 'text color',
        value: cfg.textColorScheme.label,
        onTap: _cycleSpectrumTextColor,
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _row(
        key: const ValueKey('void-settings-spectrum-media-color'),
        label: 'media controls color',
        value: cfg.mediaControlColorScheme.label,
        onTap: _cycleSpectrumMediaColor,
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _sliderRow(
        key: const ValueKey('void-settings-spectrum-text-size'),
        label: 'text size',
        valueText: '${(cfg.textScale * 100).round()}%',
        min: 0.5,
        max: 1.5,
        divisions: 10,
        currentValue: cfg.textScale,
        onChanged: (v) {
          _settings.saveScreenConfig(cfg.copyWith(textScale: v));
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _sliderRow(
        key: const ValueKey('void-settings-spectrum-vis-width'),
        label: 'visualizer width',
        valueText: '${(cfg.spectrumWidthFactor * 100).round()}%',
        min: 0.2,
        max: 1.0,
        divisions: 16,
        currentValue: cfg.spectrumWidthFactor,
        onChanged: (v) {
          _settings.saveScreenConfig(cfg.copyWith(spectrumWidthFactor: v));
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _sliderRow(
        key: const ValueKey('void-settings-spectrum-vis-height'),
        label: 'visualizer height',
        valueText: '${(cfg.spectrumHeightFactor * 100).round()}%',
        min: 0.2,
        max: 1.0,
        divisions: 16,
        currentValue: cfg.spectrumHeightFactor,
        onChanged: (v) {
          _settings.saveScreenConfig(cfg.copyWith(spectrumHeightFactor: v));
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
    ];
  }

  List<Widget> _buildDotDisplayRows(
    DotScreenConfig cfg,
    AppPalette palette,
    AppTypography typography,
    AppGeometry geometry,
  ) {
    return [
      _sliderRow(
        key: const ValueKey('void-settings-dot-sensitivity'),
        label: 'sensitivity',
        valueText: '${cfg.sensitivity.toStringAsFixed(1)}x',
        min: 0.5,
        max: 5.0,
        divisions: 45,
        currentValue: cfg.sensitivity,
        onChanged: (v) {
          _settings.saveScreenConfig(cfg.copyWith(sensitivity: v));
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _sliderRow(
        key: const ValueKey('void-settings-dot-max-size'),
        label: 'max size',
        valueText: '${cfg.maxDotSize.toStringAsFixed(0)} px',
        min: 50.0,
        max: 300.0,
        divisions: 50,
        currentValue: cfg.maxDotSize,
        onChanged: (v) {
          _settings.saveScreenConfig(cfg.copyWith(maxDotSize: v));
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _sliderRow(
        key: const ValueKey('void-settings-dot-opacity'),
        label: 'dot opacity',
        valueText: '${(cfg.dotOpacity * 100).toStringAsFixed(0)}%',
        min: 0.0,
        max: 1.0,
        divisions: 20,
        currentValue: cfg.dotOpacity,
        onChanged: (v) {
          _settings.saveScreenConfig(cfg.copyWith(dotOpacity: v));
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
      _sliderRow(
        key: const ValueKey('void-settings-dot-text-opacity'),
        label: 'text opacity',
        valueText: '${(cfg.textOpacity * 100).toStringAsFixed(0)}%',
        min: 0.0,
        max: 1.0,
        divisions: 20,
        currentValue: cfg.textOpacity,
        onChanged: (v) {
          _settings.saveScreenConfig(cfg.copyWith(textOpacity: v));
          setState(() {});
        },
        palette: palette,
        typography: typography,
        geometry: geometry,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Auto-UI-scale helpers (for the slider's display default)
  // ---------------------------------------------------------------------------

  double _effectiveAutoUiScale() {
    final view = View.of(context);
    final dpr = view.devicePixelRatio;
    if (dpr <= 0) return 1.0;
    final logicalWidth = MediaQuery.of(context).size.width;
    if (logicalWidth <= 0) return 1.0;
    return _settings.calculateSmartScaleForWidth(
      logicalWidth,
      devicePixelRatio: dpr,
    );
  }

  Widget _autoChip({
    required bool isAuto,
    required AppPalette palette,
    required AppTypography typography,
  }) {
    return GestureDetector(
      onTap: () {
        _settings.saveUiScale(-1.0);
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isAuto ? palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.divider, width: 1),
        ),
        child: Text(
          'AUTO',
          style: TextStyle(
            color: isAuto ? palette.background : palette.fgSecondary,
            fontFamily: typography.monoFamily,
            fontSize: typography.hintSize,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Row primitives
  // ---------------------------------------------------------------------------

  Widget _header(AppPalette palette, AppTypography typography) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '<',
                style: TextStyle(
                  color: palette.fgSecondary,
                  fontFamily: typography.monoFamily,
                  fontSize: typography.rowSize,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'settings',
            style: TextStyle(
              color: palette.fgPrimary,
              fontFamily: typography.monoFamily,
              fontSize: typography.rowSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(
    String text,
    AppPalette palette,
    AppTypography typography,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: palette.fgTertiary,
          fontFamily: typography.monoFamily,
          fontSize: typography.crumbSize,
          letterSpacing: 2,
        ),
      ),
    );
  }

  /// Cycle row — label, current value, tap-to-cycle.
  Widget _row({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
    required AppPalette palette,
    required AppTypography typography,
    required AppGeometry geometry,
    bool enabled = true,
  }) {
    final labelColor = enabled ? palette.fgPrimary : palette.fgTertiary;
    final valueColor = enabled ? palette.fgSecondary : palette.fgTertiary;
    return GestureDetector(
      key: key,
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: BoxConstraints(minHeight: geometry.rowHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: palette.divider,
              width: geometry.dividerThickness,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontFamily: typography.monoFamily,
                  fontSize: typography.rowSize,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontFamily: typography.monoFamily,
                fontSize: typography.rowSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Toggle row — label, on/off, tap to flip.
  Widget _toggleRow({
    required Key key,
    required String label,
    required bool value,
    required VoidCallback onToggle,
    required AppPalette palette,
    required AppTypography typography,
    required AppGeometry geometry,
  }) {
    return _row(
      key: key,
      label: label,
      value: value ? 'on' : 'off',
      onTap: onToggle,
      palette: palette,
      typography: typography,
      geometry: geometry,
    );
  }

  /// Slider row — label + value on top, Slider below, optional trailing chip.
  Widget _sliderRow({
    required Key key,
    required String label,
    required String valueText,
    required double min,
    required double max,
    required int divisions,
    required double currentValue,
    required ValueChanged<double> onChanged,
    required AppPalette palette,
    required AppTypography typography,
    required AppGeometry geometry,
    Widget? trailing,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: palette.divider,
            width: geometry.dividerThickness,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: palette.fgPrimary,
                    fontFamily: typography.monoFamily,
                    fontSize: typography.rowSize,
                  ),
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  color: palette.fgSecondary,
                  fontFamily: typography.monoFamily,
                  fontSize: typography.rowSize,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: palette.fgPrimary,
                    inactiveTrackColor: palette.divider,
                    thumbColor: palette.fgPrimary,
                    overlayColor: palette.fgPrimary.withValues(alpha: 0.12),
                    trackHeight: 2,
                  ),
                  child: Slider(
                    value: currentValue.clamp(min, max).toDouble(),
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: onChanged,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ],
      ),
    );
  }
}
