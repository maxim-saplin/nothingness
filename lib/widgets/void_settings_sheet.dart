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
/// [AppGeometry] are captured by the row builders so specs stay declarative.
class VoidSettingsSheet extends HookWidget {
  const VoidSettingsSheet({super.key});

  static Future<void> push(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const VoidSettingsSheet()),
      );

  /// Next value in [values] after [cur], wrapping around.
  static T _next<T>(List<T> values, T cur) =>
      values[(values.indexOf(cur) + 1) % values.length];

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
      () async {
        try {
          final info = await PackageInfo.fromPlatform();
          if (active) versionLabel.value = '${info.version}+${info.buildNumber}';
        } catch (_) {
          // Non-fatal — keep the placeholder.
        }
      }();
      return () => active = false;
    }, const []);

    // Permission probe — re-runnable from external-settings rows.
    final refreshPermissions = useCallback(() async {
      if (!PlatformChannels.isAndroid) return;
      final p = PlatformChannels();
      hasNotification.value = await p.isNotificationAccessGranted();
      hasAudio.value = await p.hasAudioPermission();
    }, const []);

    useEffect(() {
      refreshPermissions();
      return null;
    }, const []);

    final theme = Theme.of(context);
    final p = theme.extension<AppPalette>()!;
    final t = theme.extension<AppTypography>()!;
    final g = theme.extension<AppGeometry>()!;

    // -------------------------------------------------------------------------
    // Row handlers (side effects only — notifiers drive the rebuild).
    // -------------------------------------------------------------------------
    void cycleScreen() {
      const order = [
        ScreenType.spectrum,
        ScreenType.polo,
        ScreenType.dot,
        ScreenType.void_,
      ];
      settings.saveScreenConfig(
          switch (_next(order, settings.screenConfigNotifier.value.type)) {
        ScreenType.spectrum => const SpectrumScreenConfig(),
        ScreenType.polo => const PoloScreenConfig(),
        ScreenType.dot => const DotScreenConfig(),
        ScreenType.void_ => const VoidScreenConfig(),
      });
    }

    void cycleSpectrum<T>(
        List<T> values, T cur, SpectrumScreenConfig Function(T) build) {
      if (settings.screenConfigNotifier.value is! SpectrumScreenConfig) return;
      settings.saveScreenConfig(build(_next(values, cur)));
    }

    String uiScaleLabel() {
      final v = settings.uiScaleNotifier.value;
      return v < 0 ? 'auto' : '${v.toStringAsFixed(2)}x';
    }

    String labelFor(ScreenType type) => switch (type) {
          ScreenType.spectrum => 'spectrum',
          ScreenType.polo => 'polo',
          ScreenType.dot => 'dot',
          ScreenType.void_ => 'void',
        };

    Future<void> openNotificationSettings() async {
      await PlatformChannels().openNotificationSettings();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await refreshPermissions();
    }

    Future<void> requestMicPermission() async {
      await Permission.microphone.request();
      await refreshPermissions();
    }

    double effectiveAutoUiScale() {
      final dpr = View.of(context).devicePixelRatio;
      if (dpr <= 0) return 1.0;
      final logicalWidth = MediaQuery.of(context).size.width;
      if (logicalWidth <= 0) return 1.0;
      return settings.calculateSmartScaleForWidth(logicalWidth,
          devicePixelRatio: dpr);
    }

    // -------------------------------------------------------------------------
    // Visual primitives.
    // -------------------------------------------------------------------------
    TextStyle rowStyle(Color color) =>
        TextStyle(color: color, fontFamily: t.monoFamily, fontSize: t.rowSize);

    final rowBorder = BoxDecoration(
      border: Border(
          bottom: BorderSide(color: p.divider, width: g.dividerThickness)),
    );

    Widget autoChip({required bool isAuto}) => PressFeedback(
          onTap: () => settings.saveUiScale(-1.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isAuto ? p.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: p.divider, width: 1),
            ),
            child: Text('AUTO',
                style: TextStyle(
                  color: isAuto ? p.background : p.fgSecondary,
                  fontFamily: t.monoFamily,
                  fontSize: t.hintSize,
                  letterSpacing: 1.5,
                )),
          ),
        );

    /// Cycle/info/toggle row — label, value, tap-to-cycle. `enabled: false`
    /// renders a read-only info row (no press dip) but keeps the ValueKey so QA
    /// can find it.
    Widget row(Key key, String label, String value, VoidCallback onTap,
        {bool enabled = true}) {
      final container = Container(
        constraints: BoxConstraints(minHeight: g.rowHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: rowBorder,
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: rowStyle(enabled ? p.fgPrimary : p.fgTertiary))),
            Text(value,
                style: rowStyle(enabled ? p.fgSecondary : p.fgTertiary)),
          ],
        ),
      );
      return enabled
          ? PressFeedback(key: key, onTap: onTap, child: container)
          : KeyedSubtree(key: key, child: container);
    }

    /// Slider row — label + value on top, Slider below, optional trailing chip.
    Widget sliderRow(_Slider s) => Container(
          key: ValueKey(s.id),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: rowBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(s.label, style: rowStyle(p.fgPrimary))),
                Text(s.valueText, style: rowStyle(p.fgSecondary)),
              ]),
              Row(children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: p.fgPrimary,
                      inactiveTrackColor: p.divider,
                      thumbColor: p.fgPrimary,
                      overlayColor: p.fgPrimary.withValues(alpha: 0.12),
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
              ]),
            ],
          ),
        );

    Widget groupHeader(String text) => Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(text,
              style: TextStyle(
                color: p.fgTertiary,
                fontFamily: t.monoFamily,
                fontSize: t.crumbSize,
                letterSpacing: 2,
              )),
        );

    Widget buildSpec(Object spec) => switch (spec) {
          _Group(:final text) => groupHeader(text),
          _Cycle(:final id, :final label, :final value, :final onTap,
                  :final enabled) =>
            row(ValueKey(id), label, value, onTap, enabled: enabled),
          _Toggle(:final id, :final label, :final value, :final onTap) =>
            row(ValueKey(id), label, value ? 'on' : 'off', onTap),
          _Slider s => sliderRow(s),
          _ => const SizedBox.shrink(),
        };

    // -------------------------------------------------------------------------
    // Spec builders.
    // -------------------------------------------------------------------------
    /// Shared `text size` slider (0.5–1.5, shown as a percent). [build] returns
    /// the updated config to persist.
    _Slider textSize(
            String keyId, double scale, ScreenConfig Function(double) build) =>
        _Slider(keyId, 'text size', '${(scale * 100).round()}%', 0.5, 1.5, 10,
            scale, (v) => settings.saveScreenConfig(build(v)));

    /// A 0..1 slider rendered as a percentage. [min] defaults to 0.
    _Slider percent(String keyId, String label, double value,
            ValueChanged<double> onChanged,
            {double min = 0.0, int divisions = 20}) =>
        _Slider(keyId, label, '${(value * 100).round()}%', min, 1.0, divisions,
            value, onChanged);

    List<Object> displayRows(ScreenConfig cfg) => switch (cfg) {
          SpectrumScreenConfig() => [
              _Cycle('void-settings-spectrum-text-color', 'text color',
                  cfg.textColorScheme.label,
                  () => cycleSpectrum(SpectrumColorScheme.values,
                      cfg.textColorScheme, (v) => cfg.copyWith(textColorScheme: v))),
              _Cycle('void-settings-spectrum-media-color', 'media controls color',
                  cfg.mediaControlColorScheme.label,
                  () => cycleSpectrum(
                      SpectrumColorScheme.values, cfg.mediaControlColorScheme,
                      (v) => cfg.copyWith(mediaControlColorScheme: v))),
              textSize('void-settings-spectrum-text-size', cfg.textScale,
                  (v) => cfg.copyWith(textScale: v)),
              percent('void-settings-spectrum-vis-width', 'visualizer width',
                  cfg.spectrumWidthFactor,
                  (v) => settings.saveScreenConfig(
                      cfg.copyWith(spectrumWidthFactor: v)),
                  min: 0.2, divisions: 16),
              percent('void-settings-spectrum-vis-height', 'visualizer height',
                  cfg.spectrumHeightFactor,
                  (v) => settings.saveScreenConfig(
                      cfg.copyWith(spectrumHeightFactor: v)),
                  min: 0.2, divisions: 16),
            ],
          DotScreenConfig() => [
              // B-020 — opt-in title + parent-folder overlay (default off).
              _Toggle('void-settings-dot-show-song-info', 'show song info',
                  cfg.showSongInfo,
                  () => settings.saveScreenConfig(
                      cfg.copyWith(showSongInfo: !cfg.showSongInfo))),
              _Slider('void-settings-dot-sensitivity', 'sensitivity',
                  '${cfg.sensitivity.toStringAsFixed(1)}x', 0.5, 5.0, 45,
                  cfg.sensitivity,
                  (v) => settings.saveScreenConfig(cfg.copyWith(sensitivity: v))),
              _Slider('void-settings-dot-max-size', 'max size',
                  '${cfg.maxDotSize.toStringAsFixed(0)} px', 50.0, 300.0, 50,
                  cfg.maxDotSize,
                  (v) => settings.saveScreenConfig(cfg.copyWith(maxDotSize: v))),
              percent('void-settings-dot-opacity', 'dot opacity', cfg.dotOpacity,
                  (v) => settings.saveScreenConfig(cfg.copyWith(dotOpacity: v))),
              percent('void-settings-dot-text-opacity', 'text opacity',
                  cfg.textOpacity,
                  (v) => settings.saveScreenConfig(cfg.copyWith(textOpacity: v))),
              // B-035 — per-hero text size, shown always so users can tune before
              // enabling the overlay.
              textSize('void-settings-dot-text-size', cfg.textScale,
                  (v) => cfg.copyWith(textScale: v)),
            ],
          VoidScreenConfig() => [
              textSize('void-settings-void-text-size', cfg.textScale,
                  (v) => cfg.copyWith(textScale: v)),
            ],
          PoloScreenConfig() => [
              textSize('void-settings-polo-text-size', cfg.textScale,
                  (v) => cfg.copyWith(textScale: v)),
            ],
        };

    List<Widget> buildGroups(OperatingMode mode) {
      final isOwn = mode == OperatingMode.own;
      final isBackground = mode == OperatingMode.background;
      final cfg = settings.screenConfigNotifier.value;
      final spectrum = settings.settingsNotifier.value;

      final rows = <Object>[
        // MODE
        _Group('MODE'),
        _Cycle('void-settings-mode', 'operating mode', mode.name,
            () => settings.saveOperatingMode(_next(OperatingMode.values, mode))),

        // LOOK
        _Group('LOOK'),
        _Cycle('void-settings-theme', 'theme',
            settings.themeIdNotifier.value.storageKey,
            () => settings.saveThemeId(
                _next(ThemeId.values, settings.themeIdNotifier.value))),
        _Cycle('void-settings-variant', 'variant',
            settings.themeVariantNotifier.value.name,
            () => settings.saveThemeVariant(_next(
                const [ThemeVariant.dark, ThemeVariant.light, ThemeVariant.system],
                settings.themeVariantNotifier.value))),
        _Cycle('void-settings-screen', 'screen', labelFor(cfg.type), cycleScreen),
        _Toggle('void-settings-immersive', 'immersive',
            settings.immersiveNotifier.value,
            () => settings.setImmersive(!settings.immersiveNotifier.value)),
        // Transport strip — bottom / top / off. Browser — fixed vs swipe-up.
        _Cycle('void-settings-transport', 'transport',
            settings.transportPositionNotifier.value.label,
            () => settings.setTransportPosition(_next(TransportPosition.values,
                settings.transportPositionNotifier.value))),
        _Cycle('void-settings-browser', 'browser',
            settings.browserPresentationNotifier.value.label,
            () => settings.setBrowserPresentation(_next(
                BrowserPresentation.values,
                settings.browserPresentationNotifier.value))),
        _Toggle('void-settings-full-screen', 'full screen',
            settings.fullScreenNotifier.value,
            () => settings.setFullScreen(!settings.fullScreenNotifier.value,
                save: true)),
        _Slider('void-settings-ui-scale', 'ui scale', uiScaleLabel(), 0.75, 3.0, 9,
            settings.uiScaleNotifier.value < 0
                ? effectiveAutoUiScale()
                : settings.uiScaleNotifier.value.clamp(0.75, 3.0),
            settings.saveUiScale,
            trailing: autoChip(isAuto: settings.uiScaleNotifier.value < 0)),

        // SOUND
        if (isOwn) ...[
          _Group('SOUND'),
          // Visualizer-only rows (B-034): hidden when the active hero doesn't
          // paint the spectrum (Dot, Void). The `eq` placeholder stays.
          if (cfg.usesVisualizer) ...[
            _Cycle('void-settings-bar-count', 'bar count',
                '${spectrum.barCount.count}',
                () => settings.saveSettings(spectrum.copyWith(
                    barCount: _next(BarCount.values, spectrum.barCount)))),
            _Cycle('void-settings-bar-style', 'bar style', spectrum.barStyle.name,
                () => settings.saveSettings(spectrum.copyWith(
                    barStyle: _next(BarStyle.values, spectrum.barStyle)))),
            _Cycle('void-settings-decay-speed', 'decay speed',
                spectrum.decaySpeed.name,
                () => settings.saveSettings(spectrum.copyWith(
                    decaySpeed: _next(DecaySpeed.values, spectrum.decaySpeed)))),
            _Cycle('void-settings-visualizer-color', 'visualizer color',
                spectrum.colorScheme.label,
                () => settings.saveSettings(spectrum.copyWith(colorScheme:
                    _next(SpectrumColorScheme.values, spectrum.colorScheme)))),
          ],
          _Cycle('void-settings-eq', 'eq', 'unavailable', () {}, enabled: false),

          _Group('LIBRARY'),
          _Toggle('void-settings-scan-on-startup', 'filename fallback',
              settings.useFilenameForMetadataNotifier.value,
              () => settings.setUseFilenameForMetadata(
                  !settings.useFilenameForMetadataNotifier.value)),
          _Toggle('void-settings-smart-folders', 'smart folders',
              settings.smartFoldersPresentationNotifier.value,
              () => settings.setSmartFoldersPresentation(
                  !settings.smartFoldersPresentationNotifier.value)),
        ],

        // EXTERNAL
        if (isBackground) ...[
          _Group('EXTERNAL'),
          if (Platform.isAndroid) ...[
            _Cycle('void-settings-notification-listener', 'notification listener',
                hasNotification.value ? 'granted' : 'open settings',
                openNotificationSettings),
            _Cycle('void-settings-mic-permission', 'mic permission',
                hasAudio.value ? 'granted' : 'request', requestMicPermission),
          ],
          _Slider('void-settings-noise-gate', 'noise gate',
              '${spectrum.noiseGateDb.toStringAsFixed(0)} dB', -60, -20, 40,
              spectrum.noiseGateDb,
              (v) => settings.saveSettings(spectrum.copyWith(noiseGateDb: v))),
        ],

        // DISPLAY
        _Group('DISPLAY'),
        if (kDebugMode || (!kIsWeb && Platform.isMacOS))
          _Toggle('void-settings-debug-layout', 'debug layout',
              settings.debugLayoutNotifier.value, settings.toggleDebugLayout),
        ...displayRows(cfg),

        // ABOUT
        _Group('ABOUT'),
        _Cycle('void-settings-help', 'help', '>', () => HelpScreen.push(context)),
        _Cycle('void-settings-logs', 'logs', '>',
            () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const LogScreen()))),
        _Toggle('void-settings-audio-diagnostics', 'audio diagnostics',
            settings.audioDiagnosticsOverlayNotifier.value,
            () => settings.setAudioDiagnosticsOverlay(
                !settings.audioDiagnosticsOverlayNotifier.value)),
        _Cycle('void-settings-version', 'version', versionLabel.value, () {},
            enabled: false),
      ];

      return rows.map(buildSpec).toList();
    }

    Widget header() => Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            PressFeedback(
              onTap: () => Navigator.of(context).maybePop(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('<', style: rowStyle(p.fgSecondary)),
              ),
            ),
            const SizedBox(width: 4),
            Text('settings', style: rowStyle(p.fgPrimary)),
          ]),
        );

    /// Non-scrolling status rows between header and MODE group: queue size
    /// (read-only) and a live shuffle toggle.
    List<Widget> statusStrip(AudioPlayerProvider player) {
      final count = player.queue.length;
      return [
        buildSpec(_Cycle('void-settings-status-queue', 'queue',
            '$count ${count == 1 ? 'track' : 'tracks'}', () {}, enabled: false)),
        buildSpec(_Toggle('void-settings-status-shuffle', 'shuffle',
            player.shuffle,
            () => player.shuffle ? player.disableShuffle() : player.shuffleQueue())),
      ];
    }

    // Status strip + header live OUTSIDE the ListView so they stay pinned. The
    // provider is nullable so unit tests that don't wrap the sheet in a
    // ChangeNotifierProvider keep working — the strip is omitted.
    final player = context.watch<AudioPlayerProvider?>();

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: ValueListenableBuilder<OperatingMode>(
          valueListenable: settings.operatingModeNotifier,
          builder: (context, mode, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(),
              if (player != null && player.queue.isNotEmpty)
                ...statusStrip(player),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: buildGroups(mode),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Row specs — data, not widgets. Rendered by VoidSettingsSheet.build.
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
