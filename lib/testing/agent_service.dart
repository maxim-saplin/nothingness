import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/library_controller.dart';
import '../models/audio_track.dart';
import '../models/operating_mode.dart';
import '../models/screen_config.dart';
import '../models/theme_variant.dart';
import '../providers/audio_player_provider.dart';
import '../services/settings_service.dart';

/// Debug-only VM service extensions for agent-driven app automation.
///
/// Registers extensions under `ext.nothingness.*` that an external agent can
/// call via the Dart VM Service Protocol (observatory WebSocket).
///
/// **Generic primitives** (work for any UI):
///   - `ext.nothingness.getWidgetTree`  — element tree as text
///   - `ext.nothingness.getSemantics`   — semantics tree as text
///   - `ext.nothingness.tapByKey`       — find widget by ValueKey string and tap
///   - `ext.nothingness.getSettings`    — read all persisted settings
///   - `ext.nothingness.setSetting`     — change a setting at runtime
///
/// **Playback shortcuts** (convenience for media-related workflows):
///   - `ext.nothingness.getPlaybackState` — full playback + queue snapshot
///   - `ext.nothingness.play`
///   - `ext.nothingness.pause`
///   - `ext.nothingness.next`
///   - `ext.nothingness.prev`
///   - `ext.nothingness.setQueue`
///
/// Only registered in debug mode (`kDebugMode`). No-ops in release builds.
class AgentService {
  AgentService._();

  static AudioPlayerProvider? _provider;
  static LibraryController? _libraryController;
  static Future<void> Function()? _settingsOpener;
  static String? Function()? _routerScreenLookup;
  static bool Function()? _immersiveLookup;
  static GlobalKey<NavigatorState>? _navigatorKey;

  /// Ring buffer of layout-overflow events captured from
  /// [FlutterError.onError]. Exposed via `getOverflowReports`.
  static final Queue<Map<String, Object?>> _overflowReports =
      Queue<Map<String, Object?>>();
  static const int _maxOverflowReports = 64;

  static bool _registered = false;

  /// Register all agent extensions. Safe to call multiple times (idempotent).
  static void register({required AudioPlayerProvider provider}) {
    if (!kDebugMode || _registered) return;

    _provider = provider;
    _installOverflowHook();

    // --- Generic primitives ---
    developer.registerExtension('ext.nothingness.getWidgetTree', _getWidgetTree);
    developer.registerExtension('ext.nothingness.getSemantics', _getSemantics);
    developer.registerExtension('ext.nothingness.tapByKey', _tapByKey);
    developer.registerExtension('ext.nothingness.getSettings', _getSettings);
    developer.registerExtension('ext.nothingness.setSetting', _setSetting);

    // --- Playback shortcuts ---
    developer.registerExtension(
      'ext.nothingness.getPlaybackState',
      _getPlaybackState,
    );
    developer.registerExtension('ext.nothingness.play', _play);
    developer.registerExtension('ext.nothingness.pause', _pause);
    developer.registerExtension('ext.nothingness.next', _next);
    developer.registerExtension('ext.nothingness.prev', _prev);
    developer.registerExtension('ext.nothingness.setQueue', _setQueue);

    // --- Audio diagnostics ---
    developer.registerExtension(
      'ext.nothingness.getDiagnostics',
      _getDiagnostics,
    );
    developer.registerExtension(
      'ext.nothingness.getAudioEvents',
      _getAudioEvents,
    );
    developer.registerExtension(
      'ext.nothingness.simulateInterruption',
      _simulateInterruption,
    );
    developer.registerExtension(
      'ext.nothingness.simulateNoisy',
      _simulateNoisy,
    );

    // --- P-A inspection surface ---
    developer.registerExtension(
      'ext.nothingness.getRouterState',
      _getRouterState,
    );
    developer.registerExtension(
      'ext.nothingness.getLibraryState',
      _getLibraryState,
    );
    developer.registerExtension(
      'ext.nothingness.navigateVoid',
      _navigateVoid,
    );
    developer.registerExtension(
      'ext.nothingness.navigateVoidUp',
      _navigateVoidUp,
    );
    developer.registerExtension(
      'ext.nothingness.openSettingsSheet',
      _openSettingsSheet,
    );
    developer.registerExtension(
      'ext.nothingness.closeSettingsSheet',
      _closeSettingsSheet,
    );
    developer.registerExtension(
      'ext.nothingness.playTrackByPath',
      _playTrackByPath,
    );
    developer.registerExtension(
      'ext.nothingness.setPreference',
      _setPreference,
    );
    developer.registerExtension(
      'ext.nothingness.clearPreference',
      _clearPreference,
    );
    developer.registerExtension(
      'ext.nothingness.requestLibraryPermission',
      _requestLibraryPermission,
    );
    developer.registerExtension(
      'ext.nothingness.getOverflowReports',
      _getOverflowReports,
    );

    _registered = true;
    debugPrint('[AgentService] registered 26 VM service extensions');
  }

  // ---------------------------------------------------------------------------
  // Registry hooks — called by app code to inject references the agent needs.
  // ---------------------------------------------------------------------------

  /// Register the [LibraryController] owned by the active Void screen.
  /// VoidScreen.initState calls this; dispose() passes null.
  static void registerLibraryController(LibraryController? controller) {
    if (!kDebugMode) return;
    _libraryController = controller;
  }

  /// Register a closure that opens the settings surface appropriate for the
  /// currently active home screen (Void sheet vs. legacy settings page).
  /// MediaControllerPage owns this — it knows which screen is mounted.
  static void registerSettingsOpener(Future<void> Function()? opener) {
    if (!kDebugMode) return;
    _settingsOpener = opener;
  }

  /// Register a closure that returns the currently active home-screen name
  /// (`spectrum` / `polo` / `dot` / `void`). Called by MediaControllerPage and
  /// kept stable across screen transitions.
  static void registerScreenLookup(String? Function()? lookup) {
    if (!kDebugMode) return;
    _routerScreenLookup = lookup;
  }

  /// Register a closure that returns whether the current home screen is in an
  /// immersive (full-bleed) state. Only Void exposes a meaningful value;
  /// other screens leave this null and `getRouterState` reports `false`.
  static void registerImmersiveLookup(bool Function()? lookup) {
    if (!kDebugMode) return;
    _immersiveLookup = lookup;
  }

  /// Register the [NavigatorState] key used to push/pop routes (for closing
  /// the settings sheet from RPC, among other things).
  static void registerNavigatorKey(GlobalKey<NavigatorState>? key) {
    if (!kDebugMode) return;
    _navigatorKey = key;
  }

  // ---------------------------------------------------------------------------
  // Overflow capture
  // ---------------------------------------------------------------------------

  static void _installOverflowHook() {
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final summary = details.summary.toString();
      final ex = details.exception.toString();
      final isOverflow = summary.contains('overflow') ||
          summary.contains('OVERFLOWED') ||
          ex.contains('overflow') ||
          ex.contains('OVERFLOWED');
      if (isOverflow) {
        if (_overflowReports.length >= _maxOverflowReports) {
          _overflowReports.removeFirst();
        }
        _overflowReports.addLast({
          'when': DateTime.now().toIso8601String(),
          'summary': summary,
          'exception': ex,
          'library': details.library,
        });
      }
      // Always forward to the existing chain (preserves Flutter's red-screen
      // and the previous handler, e.g. Crashlytics).
      previous?.call(details);
    };
  }

  // ---------------------------------------------------------------------------
  // Generic primitives
  // ---------------------------------------------------------------------------

  static Future<developer.ServiceExtensionResponse> _getWidgetTree(
    String method,
    Map<String, String> params,
  ) async {
    final depth = int.tryParse(params['depth'] ?? '') ?? 0; // 0 = unlimited
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return _ok({'tree': 'no root element'});
    }
    final tree = root.toStringDeep(minLevel: DiagnosticLevel.debug);
    final truncated = _truncate(tree, depth);
    return _ok({'tree': truncated});
  }

  static Future<developer.ServiceExtensionResponse> _getSemantics(
    String method,
    Map<String, String> params,
  ) async {
    final root = WidgetsBinding.instance.rootElement
        ?.findRenderObject()
        ?.debugSemantics;
    if (root == null) {
      return _ok({'semantics': 'semantics not available'});
    }
    final text = root.toStringDeep();
    return _ok({'semantics': _truncate(text, 0)});
  }

  static Future<developer.ServiceExtensionResponse> _tapByKey(
    String method,
    Map<String, String> params,
  ) async {
    final keyValue = params['key'];
    if (keyValue == null || keyValue.isEmpty) {
      return _error('key parameter required');
    }

    final element = _findElementByKey(keyValue);
    if (element == null) {
      return _error('no widget found with key "$keyValue"');
    }

    // Walk up to find the nearest GestureDetector / InkWell / button callback.
    final tapped = _tryInvokeOnTap(element);
    if (!tapped) {
      return _error(
        'widget with key "$keyValue" found but has no tappable ancestor',
      );
    }
    return _ok({'tapped': keyValue});
  }

  static Future<developer.ServiceExtensionResponse> _getSettings(
    String method,
    Map<String, String> params,
  ) async {
    final s = SettingsService();
    return _ok({
      'screenType': s.screenConfigNotifier.value.type.name,
      'screenName': s.screenConfigNotifier.value.name,
      'debugLayout': s.debugLayoutNotifier.value,
      'fullScreen': s.fullScreenNotifier.value,
      'useFilenameForMetadata': s.useFilenameForMetadataNotifier.value,
      'uiScale': s.uiScaleNotifier.value,
      'spectrumSettings': {
        'barCount': s.settingsNotifier.value.barCount.name,
        'colorScheme': s.settingsNotifier.value.colorScheme.name,
        'barStyle': s.settingsNotifier.value.barStyle.name,
        'decaySpeed': s.settingsNotifier.value.decaySpeed.name,
        'noiseGateDb': s.settingsNotifier.value.noiseGateDb,
      },
      'operatingMode': s.operatingModeNotifier.value.name,
    });
  }

  static Future<developer.ServiceExtensionResponse> _setSetting(
    String method,
    Map<String, String> params,
  ) async {
    final name = params['name'];
    final value = params['value'];
    if (name == null || value == null) {
      return _error('name and value parameters required');
    }

    final s = SettingsService();
    switch (name) {
      case 'fullScreen':
        await s.setFullScreen(value == 'true');
      case 'debugLayout':
        s.debugLayoutNotifier.value = value == 'true';
      case 'useFilenameForMetadata':
        await s.setUseFilenameForMetadata(value == 'true');
      case 'audioDiagnosticsOverlay':
        await s.setAudioDiagnosticsOverlay(value == 'true');
      case 'screen':
        final ScreenConfig cfg;
        switch (value) {
          case 'spectrum':
            cfg = const SpectrumScreenConfig();
          case 'polo':
            cfg = const PoloScreenConfig();
          case 'dot':
            cfg = const DotScreenConfig();
          case 'void':
          case 'void_':
            cfg = const VoidScreenConfig();
          default:
            return _error(
              'unknown screen value "$value" (expected spectrum|polo|dot|void)',
            );
        }
        await s.saveScreenConfig(cfg);
      case 'themeVariant':
        final ThemeVariant v;
        switch (value) {
          case 'dark':
            v = ThemeVariant.dark;
          case 'light':
            v = ThemeVariant.light;
          case 'system':
            v = ThemeVariant.system;
          default:
            return _error(
              'unknown themeVariant value "$value" (expected dark|light|system)',
            );
        }
        await s.saveThemeVariant(v);
      case 'operatingMode':
        final OperatingMode m;
        switch (value) {
          case 'own':
            m = OperatingMode.own;
          case 'background':
            m = OperatingMode.background;
          default:
            return _error(
              'unknown operatingMode value "$value" (expected own|background)',
            );
        }
        await s.saveOperatingMode(m);
      case 'uiScale':
        final parsed = double.tryParse(value);
        if (parsed == null) {
          return _error('uiScale value "$value" is not a double');
        }
        await s.saveUiScale(parsed);
      case 'immersive':
        await s.setImmersive(value == 'true');
      default:
        return _error('unknown setting: $name');
    }
    return _ok({'set': name, 'value': value});
  }

  // ---------------------------------------------------------------------------
  // Playback shortcuts
  // ---------------------------------------------------------------------------

  static Future<developer.ServiceExtensionResponse> _getPlaybackState(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');

    final queue = p.queue;
    return _ok({
      'isPlaying': p.isPlaying,
      'currentIndex': p.currentIndex,
      'shuffle': p.shuffle,
      'queueLength': queue.length,
      'queue': queue
          .map(
            (t) => {
              'path': t.path,
              'title': t.title,
              'artist': t.artist,
              'isNotFound': t.isNotFound,
            },
          )
          .toList(growable: false),
      'songInfo': p.songInfo != null
          ? {
              'title': p.songInfo!.title,
              'artist': p.songInfo!.artist,
              'position': p.songInfo!.position,
              'duration': p.songInfo!.duration,
            }
          : null,
      'spectrumDataLength': p.spectrumData.length,
      'spectrumNonZero': p.spectrumData.any((v) => v > 0),
    });
  }

  static Future<developer.ServiceExtensionResponse> _play(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');
    if (!p.isPlaying) await p.playPause();
    return _ok({'isPlaying': true});
  }

  static Future<developer.ServiceExtensionResponse> _pause(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');
    if (p.isPlaying) await p.playPause();
    return _ok({'isPlaying': false});
  }

  static Future<developer.ServiceExtensionResponse> _next(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');
    await p.next();
    return _ok({'ok': true});
  }

  static Future<developer.ServiceExtensionResponse> _prev(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');
    await p.previous();
    return _ok({'ok': true});
  }

  static Future<developer.ServiceExtensionResponse> _setQueue(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');

    final pathsCsv = params['paths'];
    if (pathsCsv == null || pathsCsv.isEmpty) {
      return _error('paths parameter required (comma-separated)');
    }
    final startIndex = int.tryParse(params['startIndex'] ?? '0') ?? 0;
    final tracks = pathsCsv.split(',').map((path) {
      final trimmed = path.trim();
      return AudioTrack(
        path: trimmed,
        title: trimmed.split('/').last,
      );
    }).toList();

    await p.setQueue(tracks, startIndex: startIndex);
    return _ok({'queued': tracks.length, 'startIndex': startIndex});
  }

  // ---------------------------------------------------------------------------
  // Audio diagnostics
  // ---------------------------------------------------------------------------

  static Future<developer.ServiceExtensionResponse> _getDiagnostics(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');
    final snap = p.diagnosticsSnapshot();
    if (snap == null) return _ok({'snapshot': null});
    return _ok({'snapshot': snap});
  }

  static Future<developer.ServiceExtensionResponse> _getAudioEvents(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');
    return _ok({'audioEvents': p.audioEvents()});
  }

  static Future<developer.ServiceExtensionResponse> _simulateInterruption(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');

    final phase = params['phase'] ?? 'begin';
    final kind = params['kind'] ?? 'pause';
    final begin = phase == 'begin';

    final AudioInterruptionType type;
    switch (kind) {
      case 'pause':
        type = AudioInterruptionType.pause;
      case 'duck':
        type = AudioInterruptionType.duck;
      case 'unknown':
        type = AudioInterruptionType.unknown;
      default:
        return _error('unknown kind "$kind" (expected pause|duck|unknown)');
    }

    p.debugSimulateInterruption(AudioInterruptionEvent(begin, type));
    return _ok({'phase': phase, 'kind': kind});
  }

  static Future<developer.ServiceExtensionResponse> _simulateNoisy(
    String method,
    Map<String, String> params,
  ) async {
    final p = _provider;
    if (p == null) return _error('provider not registered');
    p.debugSimulateBecomingNoisy();
    return _ok({'simulated': 'noisy'});
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Find an [Element] whose widget has a [ValueKey<String>] matching [key].
  static Element? _findElementByKey(String key) {
    final targetKey = ValueKey<String>(key);
    Element? found;
    void visitor(Element element) {
      if (found != null) return;
      if (element.widget.key == targetKey) {
        found = element;
        return;
      }
      element.visitChildren(visitor);
    }
    WidgetsBinding.instance.rootElement?.visitChildren(visitor);
    return found;
  }

  /// Walk ancestors from [element] looking for a tappable callback to invoke.
  static bool _tryInvokeOnTap(Element element) {
    // Try the element itself and its ancestors.
    bool tried = false;
    void visit(Element el) {
      if (tried) return;
      final widget = el.widget;
      if (widget is GestureDetector && widget.onTap != null) {
        widget.onTap!();
        tried = true;
        return;
      }
      el.visitAncestorElements((ancestor) {
        final w = ancestor.widget;
        if (w is GestureDetector && w.onTap != null) {
          w.onTap!();
          tried = true;
          return false;
        }
        return true;
      });
    }
    visit(element);

    // Also check if the element itself or direct children have an InkWell.
    if (!tried) {
      void visitChildren(Element el) {
        if (tried) return;
        final w = el.widget;
        if (w is InkResponse && w.onTap != null) {
          w.onTap!();
          tried = true;
          return;
        }
        el.visitChildren(visitChildren);
      }
      element.visitAncestorElements((ancestor) {
        if (tried) return false;
        final w = ancestor.widget;
        if (w is InkResponse && w.onTap != null) {
          w.onTap!();
          tried = true;
          return false;
        }
        return true;
      });
      visitChildren(element);
    }
    return tried;
  }

  static String _truncate(String text, int depth) {
    // If depth > 0, limit by line count as a rough proxy.
    if (depth > 0) {
      final lines = text.split('\n');
      if (lines.length > depth) {
        return '${lines.take(depth).join('\n')}\n... (${lines.length - depth} more lines)';
      }
    }
    // Hard limit to avoid blowing up the VM service protocol.
    const maxLen = 128000;
    if (text.length > maxLen) {
      return '${text.substring(0, maxLen)}\n... (truncated at $maxLen chars)';
    }
    return text;
  }

  static developer.ServiceExtensionResponse _ok(Map<String, Object?> data) {
    return developer.ServiceExtensionResponse.result(jsonEncode(data));
  }

  static developer.ServiceExtensionResponse _error(String message) {
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      message,
    );
  }

  // ---------------------------------------------------------------------------
  // P-A inspection surface — router / library / settings / overflow.
  // ---------------------------------------------------------------------------

  static Future<developer.ServiceExtensionResponse> _getRouterState(
    String method,
    Map<String, String> params,
  ) async {
    final s = SettingsService();
    final screen = _routerScreenLookup?.call() ??
        s.screenConfigNotifier.value.type.name;
    final immersive = _immersiveLookup?.call() ?? false;
    return _ok({
      'screen': screen,
      'themeId': s.themeIdNotifier.value.storageKey,
      'themeVariant': s.themeVariantNotifier.value.name,
      'operatingMode': s.operatingModeNotifier.value.name,
      'immersive': immersive,
      'fullScreen': s.fullScreenNotifier.value,
    });
  }

  static Future<developer.ServiceExtensionResponse> _getLibraryState(
    String method,
    Map<String, String> params,
  ) async {
    final c = _libraryController;
    if (c == null) {
      return _ok({
        'registered': false,
        'message': 'no LibraryController registered (mount Void to register)',
      });
    }
    return _ok({
      'registered': true,
      'isAndroid': c.isAndroid,
      'hasPermission': c.hasPermission,
      'isLoading': c.isLoading,
      'isScanning': c.isScanning,
      'error': c.error,
      'currentPath': c.currentPath,
      'folders': c.folders
          .map((f) => {'path': f.path, 'name': f.name})
          .toList(growable: false),
      'tracks': c.tracks
          .map((t) => {
                'path': t.path,
                'title': t.title,
                'artist': t.artist,
              })
          .toList(growable: false),
      'smartRoots': c.androidSmartRootSections
          .map((s) => {
                'deviceRoot': s.deviceRoot,
                'entries': s.entries,
              })
          .toList(growable: false),
    });
  }

  static Future<developer.ServiceExtensionResponse> _navigateVoid(
    String method,
    Map<String, String> params,
  ) async {
    final path = params['path'];
    if (path == null || path.isEmpty) {
      return _error('path parameter required');
    }
    final c = _libraryController;
    if (c == null) return _error('library controller not registered');
    await c.loadFolder(path);
    return _ok({
      'currentPath': c.currentPath,
      'folders': c.folders.length,
      'tracks': c.tracks.length,
      'error': c.error,
    });
  }

  static Future<developer.ServiceExtensionResponse> _navigateVoidUp(
    String method,
    Map<String, String> params,
  ) async {
    final c = _libraryController;
    if (c == null) return _error('library controller not registered');
    await c.navigateUp();
    return _ok({
      'currentPath': c.currentPath,
      'folders': c.folders.length,
      'tracks': c.tracks.length,
    });
  }

  static Future<developer.ServiceExtensionResponse> _openSettingsSheet(
    String method,
    Map<String, String> params,
  ) async {
    final opener = _settingsOpener;
    if (opener == null) return _error('no settings opener registered');
    await opener();
    return _ok({'opened': true});
  }

  static Future<developer.ServiceExtensionResponse> _closeSettingsSheet(
    String method,
    Map<String, String> params,
  ) async {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return _error('navigator key not registered');
    final popped = await nav.maybePop();
    return _ok({'closed': popped});
  }

  static Future<developer.ServiceExtensionResponse> _playTrackByPath(
    String method,
    Map<String, String> params,
  ) async {
    final path = params['path'];
    if (path == null || path.isEmpty) return _error('path parameter required');
    final p = _provider;
    if (p == null) return _error('provider not registered');

    final track = AudioTrack(
      path: path,
      title: path.split('/').last,
    );
    await p.playOneShot(track);
    return _ok({'ok': true, 'path': path});
  }

  static Future<developer.ServiceExtensionResponse> _setPreference(
    String method,
    Map<String, String> params,
  ) async {
    final key = params['key'];
    final value = params['value'];
    final type = (params['type'] ?? 'string').toLowerCase();
    if (key == null || value == null) {
      return _error('key and value parameters required');
    }
    final prefs = await SharedPreferences.getInstance();
    switch (type) {
      case 'bool':
        await prefs.setBool(key, value == 'true');
      case 'int':
        final v = int.tryParse(value);
        if (v == null) return _error('value "$value" is not an int');
        await prefs.setInt(key, v);
      case 'double':
        final v = double.tryParse(value);
        if (v == null) return _error('value "$value" is not a double');
        await prefs.setDouble(key, v);
      case 'string':
        await prefs.setString(key, value);
      case 'stringlist':
        await prefs.setStringList(key, value.split(','));
      default:
        return _error('unknown type "$type"');
    }
    return _ok({'set': key, 'value': value, 'type': type});
  }

  static Future<developer.ServiceExtensionResponse> _clearPreference(
    String method,
    Map<String, String> params,
  ) async {
    final key = params['key'];
    if (key == null || key.isEmpty) return _error('key parameter required');
    final prefs = await SharedPreferences.getInstance();
    if (key == '*') {
      await prefs.clear();
      return _ok({'cleared': '*'});
    }
    await prefs.remove(key);
    return _ok({'cleared': key});
  }

  static Future<developer.ServiceExtensionResponse> _requestLibraryPermission(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final results = await [
        Permission.storage,
        Permission.audio,
        Permission.microphone,
      ].request();
      final granted = (results[Permission.storage]?.isGranted ?? false) ||
          (results[Permission.audio]?.isGranted ?? false);
      // Also drive the controller so its state updates.
      final c = _libraryController;
      if (c != null) {
        await c.requestPermission();
      }
      return _ok({
        'granted': granted,
        'storage': results[Permission.storage]?.name,
        'audio': results[Permission.audio]?.name,
        'microphone': results[Permission.microphone]?.name,
      });
    } catch (e) {
      return _error('requestLibraryPermission failed: $e');
    }
  }

  static Future<developer.ServiceExtensionResponse> _getOverflowReports(
    String method,
    Map<String, String> params,
  ) async {
    final clear = (params['clear'] ?? 'false') == 'true';
    final reports = _overflowReports
        .toList(growable: false)
        .map<Map<String, Object?>>((r) => Map<String, Object?>.from(r))
        .toList(growable: false);
    if (clear) _overflowReports.clear();
    return _ok({'reports': reports, 'count': reports.length});
  }
}
