import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/browser_presentation.dart';
import '../models/operating_mode.dart';
import '../models/screen_config.dart';
import '../models/spectrum_settings.dart';
import '../models/theme_id.dart';
import '../models/theme_variant.dart';
import '../models/transport_position.dart';
import '../providers/audio_player_provider.dart';
import '../screens/help_screen.dart';
import '../screens/log_screen.dart';
import '../services/platform_channels.dart';
import '../services/settings_service.dart';
import '../theme/app_geometry.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
import 'press_feedback.dart';

/// Themed settings surface for the Void chrome.
///
/// This is the single settings UI for the app. Groups (MODE / LOOK / SOUND /
/// LIBRARY / EXTERNAL / DISPLAY / ABOUT) adapt to the active operating mode
/// and the active home-screen so per-visualisation knobs only appear when
/// relevant. A pinned status strip (queue size + shuffle toggle) sits between
/// the header and the MODE group when the queue is non-empty.
///
/// Three row primitives: [_row] (cycle/info), [_sliderRow], [_toggleRow]. They
/// read the active [AppPalette] / [AppTypography] / [AppGeometry] from instance
/// fields assigned at the top of [build], so callers don't thread them through.
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

  // Active theme handles, assigned at the top of [build]. The row builders
  // read these so they don't have to thread three args through every call.
  late AppPalette _p;
  late AppTypography _t;
  late AppGeometry _g;

  // Notifiers the sheet renders against. Subscribing here lets every row pick
  // up cycle / slider mutations without each handler having to call setState —
  // mutating any watched notifier rebuilds the whole sheet.
  late final List<Listenable> _watched = <Listenable>[
    _settings.operatingModeNotifier,
    _settings.themeIdNotifier,
    _settings.themeVariantNotifier,
    _settings.screenConfigNotifier,
    _settings.immersiveNotifier,
    _settings.transportPositionNotifier,
    _settings.browserPresentationNotifier,
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
    if (mounted) setState(() {});
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

  @override
  void dispose() {
    for (final l in _watched) {
      l.removeListener(_onAnySettingChanged);
    }
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = '${info.version}+${info.buildNumber}');
    } catch (_) {
      // Non-fatal — keep the placeholder.
    }
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
  // Cycle helpers (enum-valued rows). Mutating a watched notifier rebuilds the
  // sheet, so none of these need an explicit setState.
  // ---------------------------------------------------------------------------

  /// Next value in [values] after [cur], wrapping around.
  T _next<T>(List<T> values, T cur) =>
      values[(values.indexOf(cur) + 1) % values.length];

  void _cycleMode() => _settings.saveOperatingMode(
      _next(OperatingMode.values, _settings.operatingModeNotifier.value));

  void _cycleTheme() => _settings.saveThemeId(
      _next(ThemeId.values, _settings.themeIdNotifier.value));

  void _cycleVariant() => _settings.saveThemeVariant(_next(
        const [ThemeVariant.dark, ThemeVariant.light, ThemeVariant.system],
        _settings.themeVariantNotifier.value,
      ));

  void _cycleScreen() {
    const order = [
      ScreenType.spectrum,
      ScreenType.polo,
      ScreenType.dot,
      ScreenType.void_,
    ];
    switch (_next(order, _settings.screenConfigNotifier.value.type)) {
      case ScreenType.spectrum:
        _settings.saveScreenConfig(const SpectrumScreenConfig());
      case ScreenType.polo:
        _settings.saveScreenConfig(const PoloScreenConfig());
      case ScreenType.dot:
        _settings.saveScreenConfig(const DotScreenConfig());
      case ScreenType.void_:
        _settings.saveScreenConfig(const VoidScreenConfig());
    }
  }

  void _cycleBarCount() {
    final cur = _settings.settingsNotifier.value;
    _settings.saveSettings(
        cur.copyWith(barCount: _next(BarCount.values, cur.barCount)));
  }

  void _cycleBarStyle() {
    final cur = _settings.settingsNotifier.value;
    _settings.saveSettings(
        cur.copyWith(barStyle: _next(BarStyle.values, cur.barStyle)));
  }

  void _cycleDecaySpeed() {
    final cur = _settings.settingsNotifier.value;
    _settings.saveSettings(
        cur.copyWith(decaySpeed: _next(DecaySpeed.values, cur.decaySpeed)));
  }

  void _cycleTransportPosition() => _settings.setTransportPosition(
      _next(TransportPosition.values, _settings.transportPositionNotifier.value));

  void _cycleBrowserPresentation() => _settings.setBrowserPresentation(_next(
      BrowserPresentation.values, _settings.browserPresentationNotifier.value));

  void _cycleVisualizerColor() {
    final cur = _settings.settingsNotifier.value;
    _settings.saveSettings(cur.copyWith(
        colorScheme: _next(SpectrumColorScheme.values, cur.colorScheme)));
  }

  void _cycleSpectrumTextColor() {
    final cfg = _settings.screenConfigNotifier.value;
    if (cfg is! SpectrumScreenConfig) return;
    _settings.saveScreenConfig(cfg.copyWith(
        textColorScheme:
            _next(SpectrumColorScheme.values, cfg.textColorScheme)));
  }

  void _cycleSpectrumMediaColor() {
    final cfg = _settings.screenConfigNotifier.value;
    if (cfg is! SpectrumScreenConfig) return;
    _settings.saveScreenConfig(cfg.copyWith(
        mediaControlColorScheme:
            _next(SpectrumColorScheme.values, cfg.mediaControlColorScheme)));
  }

  String _uiScaleLabel() {
    final v = _settings.uiScaleNotifier.value;
    return v < 0 ? 'auto' : '${v.toStringAsFixed(2)}x';
  }

  String _labelFor(ScreenType type) => switch (type) {
        ScreenType.spectrum => 'spectrum',
        ScreenType.polo => 'polo',
        ScreenType.dot => 'dot',
        ScreenType.void_ => 'void',
      };

  Future<void> _openNotificationSettings() async {
    await PlatformChannels().openNotificationSettings();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshPermissions();
  }

  Future<void> _requestMicPermission() async {
    await Permission.microphone.request();
    await _refreshPermissions();
  }

  Future<void> _openLogs(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const LogScreen()));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _p = theme.extension<AppPalette>()!;
    _t = theme.extension<AppTypography>()!;
    _g = theme.extension<AppGeometry>()!;

    // The status strip + header live OUTSIDE the scrolling ListView so they
    // stay pinned. The provider is nullable so unit tests that don't wrap the
    // sheet in a ChangeNotifierProvider keep working — the strip is omitted.
    final player = context.watch<AudioPlayerProvider?>();

    return Scaffold(
      backgroundColor: _p.background,
      body: SafeArea(
        child: ValueListenableBuilder<OperatingMode>(
          valueListenable: _settings.operatingModeNotifier,
          builder: (context, mode, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                if (player != null && player.queue.isNotEmpty)
                  ..._statusStrip(player),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: _buildGroups(mode),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Non-scrolling status rows inserted between the header and the MODE group:
  /// queue size (read-only) and a live shuffle toggle.
  List<Widget> _statusStrip(AudioPlayerProvider player) {
    final count = player.queue.length;
    return [
      _cycleRow((
        'void-settings-status-queue',
        'queue',
        '$count ${count == 1 ? 'track' : 'tracks'}',
        () {},
      ), enabled: false),
      _toggle((
        'void-settings-status-shuffle',
        'shuffle',
        player.shuffle,
        () => player.shuffle ? player.disableShuffle() : player.shuffleQueue(),
      )),
    ];
  }

  List<Widget> _buildGroups(OperatingMode mode) {
    final isOwn = mode == OperatingMode.own;
    final isBackground = mode == OperatingMode.background;
    final activeConfig = _settings.screenConfigNotifier.value;
    final type = activeConfig.type;
    final spectrum = _settings.settingsNotifier.value;

    return [
      // MODE
      _groupHeader('MODE'),
      _cycleRow(
          ('void-settings-mode', 'operating mode', mode.name, _cycleMode)),

      // LOOK
      _groupHeader('LOOK'),
      ...[
        ('void-settings-theme', 'theme',
            _settings.themeIdNotifier.value.storageKey, _cycleTheme),
        ('void-settings-variant', 'variant',
            _settings.themeVariantNotifier.value.name, _cycleVariant),
        ('void-settings-screen', 'screen', _labelFor(type), _cycleScreen),
      ].map(_cycleRow),
      _toggle((
        'void-settings-immersive',
        'immersive',
        _settings.immersiveNotifier.value,
        () => _settings.setImmersive(!_settings.immersiveNotifier.value),
      )),
      // Transport strip — bottom / top / off. `top` pins the strip below the
      // hero; `bottom` keeps it above the crumb; `off` hides it.
      // Browser presentation — fixed in its slot vs revealed by swipe-up.
      ...[
        ('void-settings-transport', 'transport',
            _settings.transportPositionNotifier.value.label,
            _cycleTransportPosition),
        ('void-settings-browser', 'browser',
            _settings.browserPresentationNotifier.value.label,
            _cycleBrowserPresentation),
      ].map(_cycleRow),
      _toggle((
        'void-settings-full-screen',
        'full screen',
        _settings.fullScreenNotifier.value,
        () => _settings.setFullScreen(!_settings.fullScreenNotifier.value,
            save: true),
      )),
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
        trailing: _autoChip(isAuto: _settings.uiScaleNotifier.value < 0),
        onChanged: _settings.saveUiScale,
      ),

      // SOUND
      if (isOwn) ...[
        _groupHeader('SOUND'),
        // Visualizer-only rows (B-034): hidden when the active hero doesn't
        // paint the spectrum (Dot, Void). The `eq` placeholder stays.
        if (activeConfig.usesVisualizer)
          ...[
            ('void-settings-bar-count', 'bar count',
                '${spectrum.barCount.count}', _cycleBarCount),
            ('void-settings-bar-style', 'bar style', spectrum.barStyle.name,
                _cycleBarStyle),
            ('void-settings-decay-speed', 'decay speed',
                spectrum.decaySpeed.name, _cycleDecaySpeed),
            ('void-settings-visualizer-color', 'visualizer color',
                spectrum.colorScheme.label, _cycleVisualizerColor),
          ].map(_cycleRow),
        _cycleRow(('void-settings-eq', 'eq', 'unavailable', () {}),
            enabled: false),

        _groupHeader('LIBRARY'),
        _toggle((
          'void-settings-scan-on-startup',
          'filename fallback',
          _settings.useFilenameForMetadataNotifier.value,
          () => _settings.setUseFilenameForMetadata(
              !_settings.useFilenameForMetadataNotifier.value),
        )),
        _toggle((
          'void-settings-smart-folders',
          'smart folders',
          _settings.smartFoldersPresentationNotifier.value,
          () => _settings.setSmartFoldersPresentation(
              !_settings.smartFoldersPresentationNotifier.value),
        )),
      ],

      // EXTERNAL
      if (isBackground) ...[
        _groupHeader('EXTERNAL'),
        if (Platform.isAndroid)
          ...[
            ('void-settings-notification-listener', 'notification listener',
                _hasNotification ? 'granted' : 'open settings',
                _openNotificationSettings),
            ('void-settings-mic-permission', 'mic permission',
                _hasAudio ? 'granted' : 'request', _requestMicPermission),
          ].map(_cycleRow),
        _sliderRow(
          key: const ValueKey('void-settings-noise-gate'),
          label: 'noise gate',
          valueText: '${spectrum.noiseGateDb.toStringAsFixed(0)} dB',
          min: -60,
          max: -20,
          divisions: 40,
          currentValue: spectrum.noiseGateDb,
          onChanged: (v) =>
              _settings.saveSettings(spectrum.copyWith(noiseGateDb: v)),
        ),
      ],

      // DISPLAY
      _groupHeader('DISPLAY'),
      if (kDebugMode || (!kIsWeb && Platform.isMacOS))
        _toggleRow(
          key: const ValueKey('void-settings-debug-layout'),
          label: 'debug layout',
          value: _settings.debugLayoutNotifier.value,
          onToggle: _settings.toggleDebugLayout,
        ),
      ..._buildDisplayRows(activeConfig),

      // ABOUT
      _groupHeader('ABOUT'),
      ...[
        ('void-settings-help', 'help', '>', () => HelpScreen.push(context)),
        ('void-settings-logs', 'logs', '>', () => _openLogs(context)),
      ].map(_cycleRow),
      _toggle((
        'void-settings-audio-diagnostics',
        'audio diagnostics',
        _settings.audioDiagnosticsOverlayNotifier.value,
        () => _settings.setAudioDiagnosticsOverlay(
            !_settings.audioDiagnosticsOverlayNotifier.value),
      )),
      _cycleRow(('void-settings-version', 'version', _versionLabel, () {}),
          enabled: false),
    ];
  }

  // ---------------------------------------------------------------------------
  // Screen-specific DISPLAY rows
  // ---------------------------------------------------------------------------

  List<Widget> _buildDisplayRows(ScreenConfig cfg) {
    switch (cfg) {
      case SpectrumScreenConfig():
        return [
          _cycleRow(('void-settings-spectrum-text-color', 'text color',
              cfg.textColorScheme.label, _cycleSpectrumTextColor)),
          _cycleRow(('void-settings-spectrum-media-color',
              'media controls color', cfg.mediaControlColorScheme.label,
              _cycleSpectrumMediaColor)),
          _textSizeRow('void-settings-spectrum-text-size', cfg.textScale,
              (v) => cfg.copyWith(textScale: v)),
          _percentSlider(
            keyId: 'void-settings-spectrum-vis-width',
            label: 'visualizer width',
            value: cfg.spectrumWidthFactor,
            min: 0.2,
            divisions: 16,
            onChanged: (v) =>
                _settings.saveScreenConfig(cfg.copyWith(spectrumWidthFactor: v)),
          ),
          _percentSlider(
            keyId: 'void-settings-spectrum-vis-height',
            label: 'visualizer height',
            value: cfg.spectrumHeightFactor,
            min: 0.2,
            divisions: 16,
            onChanged: (v) => _settings
                .saveScreenConfig(cfg.copyWith(spectrumHeightFactor: v)),
          ),
        ];
      case DotScreenConfig():
        return [
          // B-020 — opt-in title + parent-folder overlay (default off).
          _toggle((
            'void-settings-dot-show-song-info',
            'show song info',
            cfg.showSongInfo,
            () => _settings.saveScreenConfig(
                cfg.copyWith(showSongInfo: !cfg.showSongInfo)),
          )),
          _sliderRow(
            key: const ValueKey('void-settings-dot-sensitivity'),
            label: 'sensitivity',
            valueText: '${cfg.sensitivity.toStringAsFixed(1)}x',
            min: 0.5,
            max: 5.0,
            divisions: 45,
            currentValue: cfg.sensitivity,
            onChanged: (v) =>
                _settings.saveScreenConfig(cfg.copyWith(sensitivity: v)),
          ),
          _sliderRow(
            key: const ValueKey('void-settings-dot-max-size'),
            label: 'max size',
            valueText: '${cfg.maxDotSize.toStringAsFixed(0)} px',
            min: 50.0,
            max: 300.0,
            divisions: 50,
            currentValue: cfg.maxDotSize,
            onChanged: (v) =>
                _settings.saveScreenConfig(cfg.copyWith(maxDotSize: v)),
          ),
          _percentSlider(
            keyId: 'void-settings-dot-opacity',
            label: 'dot opacity',
            value: cfg.dotOpacity,
            onChanged: (v) =>
                _settings.saveScreenConfig(cfg.copyWith(dotOpacity: v)),
          ),
          _percentSlider(
            keyId: 'void-settings-dot-text-opacity',
            label: 'text opacity',
            value: cfg.textOpacity,
            onChanged: (v) =>
                _settings.saveScreenConfig(cfg.copyWith(textOpacity: v)),
          ),
          // B-035 — per-hero text size, shown always so users can tune before
          // enabling the overlay.
          _textSizeRow('void-settings-dot-text-size', cfg.textScale,
              (v) => cfg.copyWith(textScale: v)),
        ];
      case VoidScreenConfig():
        return [
          _textSizeRow('void-settings-void-text-size', cfg.textScale,
              (v) => cfg.copyWith(textScale: v)),
        ];
      case PoloScreenConfig():
        return [
          _textSizeRow('void-settings-polo-text-size', cfg.textScale,
              (v) => cfg.copyWith(textScale: v)),
        ];
    }
  }

  /// Shared `text size` slider (0.5–1.5, shown as a percent) used by every
  /// screen config. [build] returns the updated config to persist.
  Widget _textSizeRow(
      String keyId, double scale, ScreenConfig Function(double) build) {
    return _sliderRow(
      key: ValueKey(keyId),
      label: 'text size',
      valueText: '${(scale * 100).round()}%',
      min: 0.5,
      max: 1.5,
      divisions: 10,
      currentValue: scale,
      onChanged: (v) => _settings.saveScreenConfig(build(v)),
    );
  }

  /// A 0..1 slider rendered as a percentage. [min] defaults to 0.
  Widget _percentSlider({
    required String keyId,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    int divisions = 20,
  }) {
    return _sliderRow(
      key: ValueKey(keyId),
      label: label,
      valueText: '${(value * 100).round()}%',
      min: min,
      max: 1.0,
      divisions: divisions,
      currentValue: value,
      onChanged: onChanged,
    );
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
    return _settings.calculateSmartScaleForWidth(logicalWidth,
        devicePixelRatio: dpr);
  }

  Widget _autoChip({required bool isAuto}) {
    return PressFeedback(
      onTap: () => _settings.saveUiScale(-1.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isAuto ? _p.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _p.divider, width: 1),
        ),
        child: Text(
          'AUTO',
          style: TextStyle(
            color: isAuto ? _p.background : _p.fgSecondary,
            fontFamily: _t.monoFamily,
            fontSize: _t.hintSize,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Row primitives
  // ---------------------------------------------------------------------------

  Widget _header() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          PressFeedback(
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text('<', style: _rowStyle(_p.fgSecondary)),
            ),
          ),
          const SizedBox(width: 4),
          Text('settings', style: _rowStyle(_p.fgPrimary)),
        ],
      ),
    );
  }

  Widget _groupHeader(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: _p.fgTertiary,
          fontFamily: _t.monoFamily,
          fontSize: _t.crumbSize,
          letterSpacing: 2,
        ),
      ),
    );
  }

  TextStyle _rowStyle(Color color) =>
      TextStyle(color: color, fontFamily: _t.monoFamily, fontSize: _t.rowSize);

  BoxDecoration get _rowBorder => BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: _p.divider, width: _g.dividerThickness),
        ),
      );

  /// Builds a cycle/info [_row] from a compact `(key, label, value, onTap)`
  /// spec so caller-side row lists read as data. `enabled: false` renders a
  /// read-only info row.
  Widget _cycleRow((String, String, String, VoidCallback) spec,
          {bool enabled = true}) =>
      _row(
        key: ValueKey(spec.$1),
        label: spec.$2,
        value: spec.$3,
        onTap: spec.$4,
        enabled: enabled,
      );

  /// Builds a [_toggleRow] from a compact `(key, label, value, onToggle)` spec.
  Widget _toggle((String, String, bool, VoidCallback) spec) => _toggleRow(
        key: ValueKey(spec.$1),
        label: spec.$2,
        value: spec.$3,
        onToggle: spec.$4,
      );

  /// Cycle row — label, current value, tap-to-cycle. `enabled: false` renders
  /// a read-only info row (no press dip).
  Widget _row({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final container = Container(
      constraints: BoxConstraints(minHeight: _g.rowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: _rowBorder,
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: _rowStyle(enabled ? _p.fgPrimary : _p.fgTertiary)),
          ),
          Text(value,
              style: _rowStyle(enabled ? _p.fgSecondary : _p.fgTertiary)),
        ],
      ),
    );
    // Disabled rows still need the ValueKey so QA can find them.
    if (!enabled) return KeyedSubtree(key: key, child: container);
    return PressFeedback(key: key, onTap: onTap, child: container);
  }

  /// Toggle row — label, on/off, tap to flip.
  Widget _toggleRow({
    required Key key,
    required String label,
    required bool value,
    required VoidCallback onToggle,
  }) {
    return _row(
        key: key, label: label, value: value ? 'on' : 'off', onTap: onToggle);
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
    Widget? trailing,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: _rowBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: _rowStyle(_p.fgPrimary))),
              Text(valueText, style: _rowStyle(_p.fgSecondary)),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: _p.fgPrimary,
                    inactiveTrackColor: _p.divider,
                    thumbColor: _p.fgPrimary,
                    overlayColor: _p.fgPrimary.withValues(alpha: 0.12),
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
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ],
      ),
    );
  }
}
