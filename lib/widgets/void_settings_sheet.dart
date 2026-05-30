import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
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
/// The single settings UI for the app. Groups (MODE / LOOK / SOUND / LIBRARY /
/// EXTERNAL / DISPLAY / ABOUT) adapt to the active operating mode and active
/// home-screen so per-visualisation knobs only appear when relevant. A pinned
/// status strip (queue size + shuffle toggle) sits between the header and the
/// MODE group when the queue is non-empty.
///
/// Rows are data-driven: each is a [_Cycle], [_Toggle] or [_Slider] spec that a
/// single builder renders. The active [AppPalette] / [AppTypography] /
/// [AppGeometry] are read into instance fields at the top of [build] so the row
/// builders don't thread them through.
class VoidSettingsSheet extends HookWidget {
  const VoidSettingsSheet({super.key});

  static Future<void> push(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const VoidSettingsSheet()),
      );

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    // Mutating any watched notifier rebuilds the whole sheet, so cycle/slider
    // handlers never need an explicit setState.
    useListenable(Listenable.merge(<Listenable>[
      settings.operatingModeNotifier,
      settings.themeIdNotifier,
      settings.themeVariantNotifier,
      settings.screenConfigNotifier,
      settings.immersiveNotifier,
      settings.transportPositionNotifier,
      settings.browserPresentationNotifier,
      settings.fullScreenNotifier,
      settings.uiScaleNotifier,
      settings.settingsNotifier,
      settings.useFilenameForMetadataNotifier,
      settings.smartFoldersPresentationNotifier,
      settings.debugLayoutNotifier,
      settings.audioDiagnosticsOverlayNotifier,
      settings.eqSettingsNotifier,
    ]));

    final versionLabel = useState('...');
    final hasNotification = useState(false);
    final hasAudio = useState(false);

    useEffect(() {
      var active = true;
      Future<void> loadVersion() async {
        try {
          final info = await PackageInfo.fromPlatform();
          if (!active) return;
          versionLabel.value = '${info.version}+${info.buildNumber}';
        } catch (_) {
          // Non-fatal — keep the placeholder.
        }
      }

      loadVersion();
      return () => active = false;
    }, const []);

    // Permission probe — re-runnable from external-settings rows.
    final refreshPermissions = useCallback(() async {
      if (!PlatformChannels.isAndroid) return;
      final p = PlatformChannels();
      final notif = await p.isNotificationAccessGranted();
      final audio = await p.hasAudioPermission();
      hasNotification.value = notif;
      hasAudio.value = audio;
    }, const []);

    useEffect(() {
      refreshPermissions();
      return null;
    }, const []);

    final theme = Theme.of(context);
    return _SettingsView(
      settings: settings,
      versionLabel: versionLabel.value,
      hasNotification: hasNotification.value,
      hasAudio: hasAudio.value,
      refreshPermissions: refreshPermissions,
      p: theme.extension<AppPalette>()!,
      t: theme.extension<AppTypography>()!,
      g: theme.extension<AppGeometry>()!,
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({
    required this.settings,
    required this.versionLabel,
    required this.hasNotification,
    required this.hasAudio,
    required this.refreshPermissions,
    required AppPalette p,
    required AppTypography t,
    required AppGeometry g,
  })  : _p = p,
        _t = t,
        _g = g;

  final SettingsService settings;
  final String versionLabel;
  final bool hasNotification;
  final bool hasAudio;
  final Future<void> Function() refreshPermissions;

  SettingsService get _settings => settings;
  String get _versionLabel => versionLabel;
  bool get _hasNotification => hasNotification;
  bool get _hasAudio => hasAudio;

  final AppPalette _p;
  final AppTypography _t;
  final AppGeometry _g;

  /// Next value in [values] after [cur], wrapping around.
  T _next<T>(List<T> values, T cur) =>
      values[(values.indexOf(cur) + 1) % values.length];

  void _cycleScreen() {
    const order = [
      ScreenType.spectrum,
      ScreenType.polo,
      ScreenType.dot,
      ScreenType.void_,
    ];
    _settings.saveScreenConfig(switch (
        _next(order, _settings.screenConfigNotifier.value.type)) {
      ScreenType.spectrum => const SpectrumScreenConfig(),
      ScreenType.polo => const PoloScreenConfig(),
      ScreenType.dot => const DotScreenConfig(),
      ScreenType.void_ => const VoidScreenConfig(),
    });
  }

  void _cycleSpectrum<T>(
      List<T> values, T cur, SpectrumScreenConfig Function(T) build) {
    final cfg = _settings.screenConfigNotifier.value;
    if (cfg is! SpectrumScreenConfig) return;
    _settings.saveScreenConfig(build(_next(values, cur)));
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
    await refreshPermissions();
  }

  Future<void> _requestMicPermission() async {
    await Permission.microphone.request();
    await refreshPermissions();
  }

  Future<void> _openLogs(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const LogScreen()));

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Status strip + header live OUTSIDE the ListView so they stay pinned. The
    // provider is nullable so unit tests that don't wrap the sheet in a
    // ChangeNotifierProvider keep working — the strip is omitted.
    final player = context.watch<AudioPlayerProvider?>();

    return Scaffold(
      backgroundColor: _p.background,
      body: SafeArea(
        child: ValueListenableBuilder<OperatingMode>(
          valueListenable: _settings.operatingModeNotifier,
          builder: (context, mode, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              if (player != null && player.queue.isNotEmpty)
                ..._statusStrip(player),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: _buildGroups(context, mode),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Non-scrolling status rows between header and MODE group: queue size
  /// (read-only) and a live shuffle toggle.
  List<Widget> _statusStrip(AudioPlayerProvider player) {
    final count = player.queue.length;
    return [
      _build(_Cycle('void-settings-status-queue', 'queue',
          '$count ${count == 1 ? 'track' : 'tracks'}', () {}, enabled: false)),
      _build(_Toggle('void-settings-status-shuffle', 'shuffle', player.shuffle,
          () => player.shuffle ? player.disableShuffle() : player.shuffleQueue())),
    ];
  }

  List<Widget> _buildGroups(BuildContext context, OperatingMode mode) {
    final isOwn = mode == OperatingMode.own;
    final isBackground = mode == OperatingMode.background;
    final cfg = _settings.screenConfigNotifier.value;
    final spectrum = _settings.settingsNotifier.value;

    final rows = <Object>[
      // MODE
      _Group('MODE'),
      _Cycle('void-settings-mode', 'operating mode', mode.name,
          () => _settings.saveOperatingMode(_next(OperatingMode.values, mode))),

      // LOOK
      _Group('LOOK'),
      _Cycle('void-settings-theme', 'theme',
          _settings.themeIdNotifier.value.storageKey,
          () => _settings.saveThemeId(
              _next(ThemeId.values, _settings.themeIdNotifier.value))),
      _Cycle('void-settings-variant', 'variant',
          _settings.themeVariantNotifier.value.name,
          () => _settings.saveThemeVariant(_next(
              const [ThemeVariant.dark, ThemeVariant.light, ThemeVariant.system],
              _settings.themeVariantNotifier.value))),
      _Cycle('void-settings-screen', 'screen', _labelFor(cfg.type), _cycleScreen),
      _Toggle('void-settings-immersive', 'immersive',
          _settings.immersiveNotifier.value,
          () => _settings.setImmersive(!_settings.immersiveNotifier.value)),
      // Transport strip — bottom / top / off. Browser — fixed vs swipe-up.
      _Cycle('void-settings-transport', 'transport',
          _settings.transportPositionNotifier.value.label,
          () => _settings.setTransportPosition(_next(TransportPosition.values,
              _settings.transportPositionNotifier.value))),
      _Cycle('void-settings-browser', 'browser',
          _settings.browserPresentationNotifier.value.label,
          () => _settings.setBrowserPresentation(_next(
              BrowserPresentation.values,
              _settings.browserPresentationNotifier.value))),
      _Toggle('void-settings-full-screen', 'full screen',
          _settings.fullScreenNotifier.value,
          () => _settings.setFullScreen(!_settings.fullScreenNotifier.value,
              save: true)),
      _Slider('void-settings-ui-scale', 'ui scale', _uiScaleLabel(), 0.75, 3.0, 9,
          _settings.uiScaleNotifier.value < 0
              ? _effectiveAutoUiScale(context)
              : _settings.uiScaleNotifier.value.clamp(0.75, 3.0),
          _settings.saveUiScale,
          trailing: _autoChip(isAuto: _settings.uiScaleNotifier.value < 0)),

      // SOUND
      if (isOwn) ...[
        _Group('SOUND'),
        // Visualizer-only rows (B-034): hidden when the active hero doesn't
        // paint the spectrum (Dot, Void). The `eq` placeholder stays.
        if (cfg.usesVisualizer) ...[
          _Cycle('void-settings-bar-count', 'bar count',
              '${spectrum.barCount.count}',
              () => _settings.saveSettings(spectrum.copyWith(
                  barCount: _next(BarCount.values, spectrum.barCount)))),
          _Cycle('void-settings-bar-style', 'bar style', spectrum.barStyle.name,
              () => _settings.saveSettings(spectrum.copyWith(
                  barStyle: _next(BarStyle.values, spectrum.barStyle)))),
          _Cycle('void-settings-decay-speed', 'decay speed',
              spectrum.decaySpeed.name,
              () => _settings.saveSettings(spectrum.copyWith(
                  decaySpeed: _next(DecaySpeed.values, spectrum.decaySpeed)))),
          _Cycle('void-settings-visualizer-color', 'visualizer color',
              spectrum.colorScheme.label,
              () => _settings.saveSettings(spectrum.copyWith(colorScheme:
                  _next(SpectrumColorScheme.values, spectrum.colorScheme)))),
        ],
        _Cycle('void-settings-eq', 'eq', 'unavailable', () {}, enabled: false),

        _Group('LIBRARY'),
        _Toggle('void-settings-scan-on-startup', 'filename fallback',
            _settings.useFilenameForMetadataNotifier.value,
            () => _settings.setUseFilenameForMetadata(
                !_settings.useFilenameForMetadataNotifier.value)),
        _Toggle('void-settings-smart-folders', 'smart folders',
            _settings.smartFoldersPresentationNotifier.value,
            () => _settings.setSmartFoldersPresentation(
                !_settings.smartFoldersPresentationNotifier.value)),
      ],

      // EXTERNAL
      if (isBackground) ...[
        _Group('EXTERNAL'),
        if (Platform.isAndroid) ...[
          _Cycle('void-settings-notification-listener', 'notification listener',
              _hasNotification ? 'granted' : 'open settings',
              _openNotificationSettings),
          _Cycle('void-settings-mic-permission', 'mic permission',
              _hasAudio ? 'granted' : 'request', _requestMicPermission),
        ],
        _Slider('void-settings-noise-gate', 'noise gate',
            '${spectrum.noiseGateDb.toStringAsFixed(0)} dB', -60, -20, 40,
            spectrum.noiseGateDb,
            (v) => _settings.saveSettings(spectrum.copyWith(noiseGateDb: v))),
      ],

      // DISPLAY
      _Group('DISPLAY'),
      if (kDebugMode || (!kIsWeb && Platform.isMacOS))
        _Toggle('void-settings-debug-layout', 'debug layout',
            _settings.debugLayoutNotifier.value, _settings.toggleDebugLayout),
      ..._displayRows(cfg),

      // ABOUT
      _Group('ABOUT'),
      _Cycle('void-settings-help', 'help', '>', () => HelpScreen.push(context)),
      _Cycle('void-settings-logs', 'logs', '>', () => _openLogs(context)),
      _Toggle('void-settings-audio-diagnostics', 'audio diagnostics',
          _settings.audioDiagnosticsOverlayNotifier.value,
          () => _settings.setAudioDiagnosticsOverlay(
              !_settings.audioDiagnosticsOverlayNotifier.value)),
      _Cycle('void-settings-version', 'version', _versionLabel, () {},
          enabled: false),
    ];

    return rows.map(_build).toList();
  }

  // ---------------------------------------------------------------------------
  // Screen-specific DISPLAY rows
  // ---------------------------------------------------------------------------

  List<Object> _displayRows(ScreenConfig cfg) {
    switch (cfg) {
      case SpectrumScreenConfig():
        return [
          _Cycle('void-settings-spectrum-text-color', 'text color',
              cfg.textColorScheme.label,
              () => _cycleSpectrum(SpectrumColorScheme.values,
                  cfg.textColorScheme, (v) => cfg.copyWith(textColorScheme: v))),
          _Cycle('void-settings-spectrum-media-color', 'media controls color',
              cfg.mediaControlColorScheme.label,
              () => _cycleSpectrum(
                  SpectrumColorScheme.values, cfg.mediaControlColorScheme,
                  (v) => cfg.copyWith(mediaControlColorScheme: v))),
          _textSize('void-settings-spectrum-text-size', cfg.textScale,
              (v) => cfg.copyWith(textScale: v)),
          _percent('void-settings-spectrum-vis-width', 'visualizer width',
              cfg.spectrumWidthFactor,
              (v) => _settings.saveScreenConfig(
                  cfg.copyWith(spectrumWidthFactor: v)),
              min: 0.2, divisions: 16),
          _percent('void-settings-spectrum-vis-height', 'visualizer height',
              cfg.spectrumHeightFactor,
              (v) => _settings.saveScreenConfig(
                  cfg.copyWith(spectrumHeightFactor: v)),
              min: 0.2, divisions: 16),
        ];
      case DotScreenConfig():
        return [
          // B-020 — opt-in title + parent-folder overlay (default off).
          _Toggle('void-settings-dot-show-song-info', 'show song info',
              cfg.showSongInfo,
              () => _settings.saveScreenConfig(
                  cfg.copyWith(showSongInfo: !cfg.showSongInfo))),
          _Slider('void-settings-dot-sensitivity', 'sensitivity',
              '${cfg.sensitivity.toStringAsFixed(1)}x', 0.5, 5.0, 45,
              cfg.sensitivity,
              (v) => _settings.saveScreenConfig(cfg.copyWith(sensitivity: v))),
          _Slider('void-settings-dot-max-size', 'max size',
              '${cfg.maxDotSize.toStringAsFixed(0)} px', 50.0, 300.0, 50,
              cfg.maxDotSize,
              (v) => _settings.saveScreenConfig(cfg.copyWith(maxDotSize: v))),
          _percent('void-settings-dot-opacity', 'dot opacity', cfg.dotOpacity,
              (v) => _settings.saveScreenConfig(cfg.copyWith(dotOpacity: v))),
          _percent('void-settings-dot-text-opacity', 'text opacity',
              cfg.textOpacity,
              (v) => _settings.saveScreenConfig(cfg.copyWith(textOpacity: v))),
          // B-035 — per-hero text size, shown always so users can tune before
          // enabling the overlay.
          _textSize('void-settings-dot-text-size', cfg.textScale,
              (v) => cfg.copyWith(textScale: v)),
        ];
      case VoidScreenConfig():
        return [
          _textSize('void-settings-void-text-size', cfg.textScale,
              (v) => cfg.copyWith(textScale: v)),
        ];
      case PoloScreenConfig():
        return [
          _textSize('void-settings-polo-text-size', cfg.textScale,
              (v) => cfg.copyWith(textScale: v)),
        ];
    }
  }

  /// Shared `text size` slider (0.5–1.5, shown as a percent). [build] returns
  /// the updated config to persist.
  _Slider _textSize(
          String keyId, double scale, ScreenConfig Function(double) build) =>
      _Slider(keyId, 'text size', '${(scale * 100).round()}%', 0.5, 1.5, 10,
          scale, (v) => _settings.saveScreenConfig(build(v)));

  /// A 0..1 slider rendered as a percentage. [min] defaults to 0.
  _Slider _percent(String keyId, String label, double value,
          ValueChanged<double> onChanged,
          {double min = 0.0, int divisions = 20}) =>
      _Slider(keyId, label, '${(value * 100).round()}%', min, 1.0, divisions,
          value, onChanged);

  double _effectiveAutoUiScale(BuildContext context) {
    final dpr = View.of(context).devicePixelRatio;
    if (dpr <= 0) return 1.0;
    final logicalWidth = MediaQuery.of(context).size.width;
    if (logicalWidth <= 0) return 1.0;
    return _settings.calculateSmartScaleForWidth(logicalWidth,
        devicePixelRatio: dpr);
  }

  Widget _autoChip({required bool isAuto}) => PressFeedback(
        onTap: () => _settings.saveUiScale(-1.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isAuto ? _p.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _p.divider, width: 1),
          ),
          child: Text('AUTO',
              style: TextStyle(
                color: isAuto ? _p.background : _p.fgSecondary,
                fontFamily: _t.monoFamily,
                fontSize: _t.hintSize,
                letterSpacing: 1.5,
              )),
        ),
      );

  // ---------------------------------------------------------------------------
  // Row rendering
  // ---------------------------------------------------------------------------

  Widget _build(Object spec) => switch (spec) {
        _Group(:final text) => _groupHeader(text),
        _Cycle(:final id, :final label, :final value, :final onTap,
                :final enabled) =>
          _row(ValueKey(id), label, value, onTap, enabled: enabled),
        _Toggle(:final id, :final label, :final value, :final onTap) =>
          _row(ValueKey(id), label, value ? 'on' : 'off', onTap),
        _Slider s => _sliderRow(s),
        _ => const SizedBox.shrink(),
      };

  Widget _header(BuildContext context) => Container(
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

  Widget _groupHeader(String text) => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text(text,
            style: TextStyle(
              color: _p.fgTertiary,
              fontFamily: _t.monoFamily,
              fontSize: _t.crumbSize,
              letterSpacing: 2,
            )),
      );

  TextStyle _rowStyle(Color color) =>
      TextStyle(color: color, fontFamily: _t.monoFamily, fontSize: _t.rowSize);

  BoxDecoration get _rowBorder => BoxDecoration(
        border: Border(
            bottom: BorderSide(color: _p.divider, width: _g.dividerThickness)),
      );

  /// Cycle/info/toggle row — label, value, tap-to-cycle. `enabled: false`
  /// renders a read-only info row (no press dip) but keeps the ValueKey so QA
  /// can find it.
  Widget _row(Key key, String label, String value, VoidCallback onTap,
      {bool enabled = true}) {
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
    if (!enabled) return KeyedSubtree(key: key, child: container);
    return PressFeedback(key: key, onTap: onTap, child: container);
  }

  /// Slider row — label + value on top, Slider below, optional trailing chip.
  Widget _sliderRow(_Slider s) => Container(
        key: ValueKey(s.id),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: _rowBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(s.label, style: _rowStyle(_p.fgPrimary))),
                Text(s.valueText, style: _rowStyle(_p.fgSecondary)),
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
                      value: s.currentValue.clamp(s.min, s.max).toDouble(),
                      min: s.min,
                      max: s.max,
                      divisions: s.divisions,
                      onChanged: s.onChanged,
                    ),
                  ),
                ),
                if (s.trailing != null) ...[
                  const SizedBox(width: 8),
                  s.trailing!,
                ],
              ],
            ),
          ],
        ),
      );
}

// -----------------------------------------------------------------------------
// Row specs — data, not widgets. Rendered by [_VoidSettingsSheetState._build].
// -----------------------------------------------------------------------------

class _Group {
  const _Group(this.text);
  final String text;
}

class _Cycle {
  const _Cycle(this.id, this.label, this.value, this.onTap,
      {this.enabled = true});
  final String id;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool enabled;
}

class _Toggle {
  const _Toggle(this.id, this.label, this.value, this.onTap);
  final String id;
  final String label;
  final bool value;
  final VoidCallback onTap;
}

class _Slider {
  const _Slider(this.id, this.label, this.valueText, this.min, this.max,
      this.divisions, this.currentValue, this.onChanged,
      {this.trailing});
  final String id;
  final String label;
  final String valueText;
  final double min;
  final double max;
  final int divisions;
  final double currentValue;
  final ValueChanged<double> onChanged;
  final Widget? trailing;
}
