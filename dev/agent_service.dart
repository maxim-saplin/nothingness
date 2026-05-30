import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nothingness/controllers/library_controller.dart';
import 'package:nothingness/debug_hooks.dart';
import 'package:nothingness/models/audio_track.dart';
import 'package:nothingness/models/browser_presentation.dart';
import 'package:nothingness/models/operating_mode.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/theme_variant.dart';
import 'package:nothingness/models/transport_position.dart';
import 'package:nothingness/services/playback_controller.dart';
import 'package:nothingness/services/settings_service.dart';

/// Short alias for the response future returned by every handler.
typedef _R = Future<developer.ServiceExtensionResponse>;

/// Signature for a VM service extension handler.
typedef _Handler = _R Function(String method, Map<String, String> params);

/// Signature for a handler that requires the registered provider.
typedef _PHandler = _R Function(PlaybackController p, Map<String, String> p2);

/// Debug-only VM service extensions for agent-driven app automation.
///
/// Registers one `ext.nothingness.<name>` extension per entry in [_extensions]
/// (the authoritative list) so an external agent can call them via the Dart VM
/// Service Protocol. Only active in debug mode (`kDebugMode`); a no-op in
/// release builds.
class AgentService {
  AgentService._();

  /// Ring buffer of layout-overflow events; exposed via `getOverflowReports`.
  static final Queue<Map<String, Object?>> _overflowReports =
      Queue<Map<String, Object?>>();
  static const int _maxOverflowReports = 64;

  static bool _installed = false;

  /// Short name → handler; `ext.nothingness.` is prepended at registration.
  /// This map IS the external contract drive.py relies on (one RPC per entry).
  static final Map<String, _Handler> _extensions = <String, _Handler>{
    // Generic primitives.
    'getWidgetTree': _getWidgetTree,
    'getSemantics': _getSemantics,
    'tapByKey': _tapByKey,
    'getSettings': _getSettings,
    'setSetting': _setSetting,
    // Playback shortcuts.
    'getPlaybackState': _withProvider(_getPlaybackState),
    'play': _withProvider(_play),
    'pause': _withProvider(_pause),
    'next': _withProvider(_next),
    'prev': _withProvider(_prev),
    'setQueue': _withProvider(_setQueue),
    // Audio diagnostics.
    'getDiagnostics': _withProvider(_getDiagnostics),
    'getAudioEvents': _withProvider(_getAudioEvents),
    'simulateInterruption': _withProvider(_simulateInterruption),
    'simulateNoisy': _withProvider(_simulateNoisy),
    // P-A inspection surface.
    'getRouterState': _getRouterState,
    'getLibraryState': _getLibraryState,
    'navigateVoid': _navigateVoid,
    'navigateVoidUp': _navigateVoidUp,
    'openSettingsSheet': _openSettingsSheet,
    'closeSettingsSheet': _closeSettingsSheet,
    'playTrackByPath': _playTrackByPath,
    'setPreference': _setPreference,
    'clearPreference': _clearPreference,
    'requestLibraryPermission': _requestLibraryPermission,
    'getOverflowReports': _getOverflowReports,
    'screenshot': _screenshot,
  };

  /// Install the harness: arm the overflow hook now and defer VM-service
  /// extension registration to [DebugHooks.onAppReady] (fired by the app once
  /// init completes). Safe to call multiple times (idempotent); a no-op
  /// outside debug mode.
  static void install() {
    if (!kDebugMode || _installed) return;
    _installed = true;
    _installOverflowHook();
    DebugHooks.onAppReady = (_) => _registerExtensions();
  }

  /// Register all agent extensions (one `ext.nothingness.<name>` per entry).
  static void _registerExtensions() {
    _extensions.forEach((name, handler) {
      developer.registerExtension('ext.nothingness.$name', handler);
    });
    debugPrint(
      '[AgentService] registered ${_extensions.length} VM service extensions',
    );
  }

  static void _installOverflowHook() {
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final summary = details.summary.toString();
      final ex = details.exception.toString();
      final isOverflow =
          summary.contains('overflow') ||
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

  static developer.ServiceExtensionResponse _ok(Map<String, Object?> data) =>
      developer.ServiceExtensionResponse.result(jsonEncode(data));

  /// Wraps a provider-requiring handler, erroring when none is registered.
  static _Handler _withProvider(_PHandler fn) => (method, params) async {
    final p = DebugHooks.provider as PlaybackController?;
    return p == null ? _error('provider not registered') : fn(p, params);
  };

  static developer.ServiceExtensionResponse _error(String message) =>
      developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        message,
      );

  /// Depth-first pre-order walk of [root]'s subtree; stops when [visit] returns
  /// true. When [includeSelf] is set, [root] is offered before its children.
  static bool _walkSubtree(
    Element root,
    bool Function(Element) visit, {
    bool includeSelf = false,
  }) {
    var matched = false;
    void recurse(Element el, bool offerSelf) {
      if (matched) return;
      if (offerSelf && visit(el)) {
        matched = true;
        return;
      }
      el.visitChildren((child) => recurse(child, true));
    }

    recurse(root, includeSelf);
    return matched;
  }

  /// Find an [Element] whose widget has a [ValueKey<String>] matching [key].
  static Element? _findElementByKey(String key) {
    final targetKey = ValueKey<String>(key);
    Element? found;
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    _walkSubtree(root, (el) {
      if (el.widget.key == targetKey) {
        found = el;
        return true;
      }
      return false;
    }, includeSelf: true);
    return found;
  }

  /// The `onTap` of [el]'s widget (GestureDetector/InkResponse), else null.
  static VoidCallback? _onTapOf(Element el) {
    final w = el.widget;
    if (w is GestureDetector) return w.onTap;
    if (w is InkResponse) return w.onTap;
    return null;
  }

  /// Invoke the first `onTap` found in [root]'s subtree; true if one fired.
  static bool _invokeOnTapInSubtree(Element root) => _walkSubtree(root, (el) {
    final onTap = _onTapOf(el);
    if (onTap != null) {
      onTap();
      return true;
    }
    return false;
  });

  /// Invoke the first `onTap` on [element], its ancestors, then its subtree.
  static bool _invokeOnTapAncestor(Element element) {
    final self = _onTapOf(element);
    if (self != null) {
      self();
      return true;
    }
    var fired = false;
    element.visitAncestorElements((ancestor) {
      final onTap = _onTapOf(ancestor);
      if (onTap != null) {
        onTap();
        fired = true;
        return false;
      }
      return true;
    });
    if (!fired) fired = _invokeOnTapInSubtree(element);
    return fired;
  }

  /// Synthetic pointer down/up at [element]'s RenderBox center; returns the
  /// global `{x, y}` point, or null when there is no usable box.
  static Map<String, double>? _dispatchSyntheticTap(Element element) {
    final ro = element.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    final size = ro.size;
    if (size.isEmpty) return null;
    final center = ro.localToGlobal(size.center(Offset.zero));

    final binding = GestureBinding.instance;
    // Monotonically-increasing synthetic pointer id so consecutive taps don't
    // collide in the gesture arena.
    _syntheticPointerSeq++;
    final pointer = 0x70000 | (_syntheticPointerSeq & 0xFFFF);
    final t0 = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);
    final t1 = t0 + const Duration(milliseconds: 16);

    // PointerAdded → Down → Up → Removed mirrors a real touch (the down/up
    // pair alone is unreliable on the live binding's gesture arena).
    binding
      ..handlePointerEvent(
        PointerAddedEvent(pointer: pointer, position: center, timeStamp: t0),
      )
      ..handlePointerEvent(
        PointerDownEvent(pointer: pointer, position: center, timeStamp: t0),
      )
      ..handlePointerEvent(
        PointerUpEvent(pointer: pointer, position: center, timeStamp: t1),
      )
      ..handlePointerEvent(
        PointerRemovedEvent(pointer: pointer, position: center, timeStamp: t1),
      );

    return {'x': center.dx, 'y': center.dy};
  }

  static int _syntheticPointerSeq = 0;

  static String _truncate(String text, int depth) {
    if (depth > 0) {
      final lines = text.split('\n');
      if (lines.length > depth) {
        return '${lines.take(depth).join('\n')}\n'
            '... (${lines.length - depth} more lines)';
      }
    }
    // Hard limit to avoid blowing up the VM service protocol.
    const maxLen = 128000;
    if (text.length > maxLen) {
      return '${text.substring(0, maxLen)}\n... (truncated at $maxLen chars)';
    }
    return text;
  }

  static _R _getWidgetTree(String method, Map<String, String> params) async {
    final depth = int.tryParse(params['depth'] ?? '') ?? 0; // 0 = unlimited
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return _ok({'tree': 'no root element'});
    final tree = root.toStringDeep(minLevel: DiagnosticLevel.debug);
    return _ok({'tree': _truncate(tree, depth)});
  }

  static _R _getSemantics(String method, Map<String, String> params) async {
    final root = WidgetsBinding.instance.rootElement
        ?.findRenderObject()
        ?.debugSemantics;
    if (root == null) return _ok({'semantics': 'semantics not available'});
    return _ok({'semantics': _truncate(root.toStringDeep(), 0)});
  }

  static _R _tapByKey(String method, Map<String, String> params) async {
    final keyValue = params['key'];
    if (keyValue == null || keyValue.isEmpty) {
      return _error('key parameter required');
    }

    final element = _findElementByKey(keyValue);
    if (element == null) {
      return _error('no widget found with key "$keyValue"');
    }

    // B-025: prefer a descendant-subtree callback walk (covers B-012's keyed
    // wrapper + inner GestureDetector without the live pointer pipeline).
    if (_invokeOnTapInSubtree(element)) {
      return _ok({'tapped': keyValue, 'mode': 'descendant-callback'});
    }

    // Fallback: synthetic tap at the RenderBox center (Listener/MouseRegion).
    final dispatched = _dispatchSyntheticTap(element);
    if (dispatched != null) {
      return _ok({'tapped': keyValue, 'mode': 'synthetic', 'at': dispatched});
    }

    // Legacy ancestor walk (rare: keyed node with no box/descendant callback).
    if (_invokeOnTapAncestor(element)) {
      return _ok({'tapped': keyValue, 'mode': 'ancestor-callback'});
    }

    return _error(
      'widget with key "$keyValue" found but has no descendant callback, '
      'no RenderBox, and no tappable ancestor',
    );
  }

  static _R _getSettings(String method, Map<String, String> params) async {
    final s = SettingsService();
    final frame = s.phoneFrameNotifier.value;
    return _ok({
      'screenType': s.screenConfigNotifier.value.type.name,
      'screenName': s.screenConfigNotifier.value.name,
      'debugLayout': s.debugLayoutNotifier.value,
      'fullScreen': s.fullScreenNotifier.value,
      'phoneFrame': frame == null
          ? null
          : '${frame.width.round()}x${frame.height.round()}',
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

  static _R _setSetting(String method, Map<String, String> params) async {
    final name = params['name'];
    final value = params['value'];
    if (name == null || value == null) {
      return _error('name and value parameters required');
    }

    final s = SettingsService();
    switch (name) {
      case 'fullScreen':
        await s.setFullScreen(value == 'true');
      case 'phoneFrame':
        // B-042: "off"/"none" clears; "WxH" (e.g. "390x844") sets the frame.
        final lc = value.trim().toLowerCase();
        if (lc == 'off' || lc == 'none' || lc.isEmpty) {
          await s.setPhoneFrame(null);
        } else {
          final parts = lc.split('x');
          final w = parts.length == 2 ? double.tryParse(parts[0].trim()) : null;
          final h = parts.length == 2 ? double.tryParse(parts[1].trim()) : null;
          if (w == null || h == null || w <= 0 || h <= 0) {
            return _error('phoneFrame expects "WxH" (e.g. 390x844) or "off"');
          }
          await s.setPhoneFrame(Size(w, h));
        }
      case 'debugLayout':
        s.debugLayoutNotifier.value = value == 'true';
      case 'useFilenameForMetadata':
        await s.setUseFilenameForMetadata(value == 'true');
      case 'audioDiagnosticsOverlay':
        await s.setAudioDiagnosticsOverlay(value == 'true');
      case 'screen':
        const m = {
          'spectrum': ScreenType.spectrum,
          'polo': ScreenType.polo,
          'dot': ScreenType.dot,
          'void': ScreenType.void_,
          'void_': ScreenType.void_,
        };
        final t = m[value];
        if (t == null) {
          return _error(
            'unknown screen value "$value" (expected spectrum|polo|dot|void)',
          );
        }
        // B-023: resolve via main.dart's load path so persisted per-skin
        // fields survive; const default only when nothing is persisted.
        await s.saveScreenConfig(await _resolveScreenConfig(t));
      case 'themeVariant':
        const m = {
          'dark': ThemeVariant.dark,
          'light': ThemeVariant.light,
          'system': ThemeVariant.system,
        };
        final v = m[value];
        if (v == null) {
          return _error(
            'unknown themeVariant value "$value" (expected dark|light|system)',
          );
        }
        await s.saveThemeVariant(v);
      case 'operatingMode':
        const m = {
          'own': OperatingMode.own,
          'background': OperatingMode.background,
        };
        final v = m[value];
        if (v == null) {
          return _error(
            'unknown operatingMode value "$value" (expected own|background)',
          );
        }
        await s.saveOperatingMode(v);
      case 'uiScale':
        final parsed = double.tryParse(value);
        if (parsed == null) {
          return _error('uiScale value "$value" is not a double');
        }
        await s.saveUiScale(parsed);
      case 'immersive':
        await s.setImmersive(value == 'true');
      case 'transport':
        // B-022: route through the same notifier the in-app settings UI uses
        // so the chrome updates live without an app restart.
        const m = {
          'top': TransportPosition.top,
          'bottom': TransportPosition.bottom,
          'off': TransportPosition.off,
        };
        final v = m[value];
        if (v == null) {
          return _error(
            'unknown transport value "$value" (expected top|bottom|off)',
          );
        }
        await s.setTransportPosition(v);
      case 'browserPresentation':
      case 'browser_presentation':
        // B-031: expose the browser presentation toggle for smoke tests.
        const m = {
          'fixed': BrowserPresentation.fixed,
          'swipe_up': BrowserPresentation.swipeUp,
          'swipeUp': BrowserPresentation.swipeUp,
        };
        final v = m[value];
        if (v == null) {
          return _error(
            'unknown browserPresentation value "$value" '
            '(expected fixed|swipe_up)',
          );
        }
        await s.setBrowserPresentation(v);
      default:
        return _error('unknown setting: $name');
    }
    return _ok({'set': name, 'value': value});
  }

  static Future<ScreenConfig> _resolveScreenConfig(ScreenType type) async {
    // Prefer the live in-memory config when it already matches the target
    // type (captures unsaved-to-disk runtime mutations).
    final live = SettingsService().screenConfigNotifier.value;
    if (live.type == type) return live;

    // B-028: read the per-screen `screen_config_<id>` blob (loadScreenConfig
    // also runs the one-shot legacy migration on first call).
    final persisted = await SettingsService().loadScreenConfig(
      SettingsService.screenIdForType(type),
    );
    if (persisted != null) return persisted;

    // No persisted config of this type — return the const default.
    switch (type) {
      case ScreenType.spectrum:
        return const SpectrumScreenConfig();
      case ScreenType.polo:
        return const PoloScreenConfig();
      case ScreenType.dot:
        return const DotScreenConfig();
      case ScreenType.void_:
        return const VoidScreenConfig();
    }
  }

  static _R _getPlaybackState(
    PlaybackController p,
    Map<String, String> params,
  ) async {
    final info = p.songInfo;
    return _ok({
      'isPlaying': p.isPlaying,
      'currentIndex': p.currentIndex,
      'shuffle': p.shuffle,
      'queueLength': p.queue.length,
      'queue': p.queue
          .map(
            (t) => {
              'path': t.path,
              'title': t.title,
              'artist': t.artist,
              'isNotFound': t.isNotFound,
            },
          )
          .toList(growable: false),
      'songInfo': info == null
          ? null
          : {
              'title': info.title,
              'artist': info.artist,
              'position': info.position,
              'duration': info.duration,
              // B-015: expose the path so tests can compare dirname(path).
              'path': info.track.path,
            },
      'spectrumDataLength': p.spectrumData.length,
      'spectrumNonZero': p.spectrumData.any((v) => v > 0),
    });
  }

  static _R _play(PlaybackController p, Map<String, String> params) async {
    if (!p.isPlaying) await p.playPause();
    return _ok({'isPlaying': true});
  }

  static _R _pause(PlaybackController p, Map<String, String> params) async {
    if (p.isPlaying) await p.playPause();
    return _ok({'isPlaying': false});
  }

  static _R _next(PlaybackController p, Map<String, String> params) async {
    await p.next();
    return _ok({'ok': true});
  }

  static _R _prev(PlaybackController p, Map<String, String> params) async {
    await p.previous();
    return _ok({'ok': true});
  }

  static _R _setQueue(PlaybackController p, Map<String, String> params) async {
    final pathsCsv = params['paths'];
    if (pathsCsv == null || pathsCsv.isEmpty) {
      return _error('paths parameter required (comma-separated)');
    }
    final startIndex = int.tryParse(params['startIndex'] ?? '0') ?? 0;
    final tracks = pathsCsv.split(',').map((path) {
      final trimmed = path.trim();
      return AudioTrack(path: trimmed, title: trimmed.split('/').last);
    }).toList();

    await p.setQueue(tracks, startIndex: startIndex);
    return _ok({'queued': tracks.length, 'startIndex': startIndex});
  }

  static _R _getDiagnostics(
    PlaybackController p,
    Map<String, String> params,
  ) async => _ok({'snapshot': p.diagnosticsSnapshot()});

  static _R _getAudioEvents(
    PlaybackController p,
    Map<String, String> params,
  ) async => _ok({'audioEvents': p.audioEvents()});

  static _R _simulateInterruption(
    PlaybackController p,
    Map<String, String> params,
  ) async {
    final phase = params['phase'] ?? 'begin';
    final kind = params['kind'] ?? 'pause';
    const types = {
      'pause': AudioInterruptionType.pause,
      'duck': AudioInterruptionType.duck,
      'unknown': AudioInterruptionType.unknown,
    };
    final type = types[kind];
    if (type == null) {
      return _error('unknown kind "$kind" (expected pause|duck|unknown)');
    }

    p.debugSimulateInterruption(AudioInterruptionEvent(phase == 'begin', type));
    return _ok({'phase': phase, 'kind': kind});
  }

  static _R _simulateNoisy(
    PlaybackController p,
    Map<String, String> params,
  ) async {
    p.debugSimulateBecomingNoisy();
    return _ok({'simulated': 'noisy'});
  }

  static _R _getRouterState(String method, Map<String, String> params) async {
    final s = SettingsService();
    return _ok({
      'screen': DebugHooks.screenLookup?.call() ??
          s.screenConfigNotifier.value.type.name,
      'themeId': s.themeIdNotifier.value.storageKey,
      'themeVariant': s.themeVariantNotifier.value.name,
      'operatingMode': s.operatingModeNotifier.value.name,
      'immersive': DebugHooks.immersiveLookup?.call() ?? false,
      'fullScreen': s.fullScreenNotifier.value,
    });
  }

  static _R _getLibraryState(String method, Map<String, String> params) async {
    final c = DebugHooks.libraryController as LibraryController?;
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
          .map((t) => {'path': t.path, 'title': t.title, 'artist': t.artist})
          .toList(growable: false),
      'smartRoots': c.androidSmartRootSections
          .map((s) => {'deviceRoot': s.deviceRoot, 'entries': s.entries})
          .toList(growable: false),
    });
  }

  static _R _navigateVoid(String method, Map<String, String> params) async {
    final path = params['path'];
    if (path == null || path.isEmpty) return _error('path parameter required');
    final c = DebugHooks.libraryController as LibraryController?;
    if (c == null) return _error('library controller not registered');
    await c.loadFolder(path);
    return _ok({
      'currentPath': c.currentPath,
      'folders': c.folders.length,
      'tracks': c.tracks.length,
      'error': c.error,
    });
  }

  static _R _navigateVoidUp(String method, Map<String, String> params) async {
    final c = DebugHooks.libraryController as LibraryController?;
    if (c == null) return _error('library controller not registered');
    await c.navigateUp();
    return _ok({
      'currentPath': c.currentPath,
      'folders': c.folders.length,
      'tracks': c.tracks.length,
    });
  }

  static _R _openSettingsSheet(
    String method,
    Map<String, String> params,
  ) async {
    final opener = DebugHooks.settingsOpener;
    if (opener == null) return _error('no settings opener registered');
    // B-024: fire-and-forget. Openers do `Navigator.push`, whose Future only
    // completes when the route pops — awaiting it would hang the RPC.
    unawaited(
      opener().catchError((Object e, StackTrace st) {
        debugPrint('[AgentService] openSettingsSheet opener threw: $e\n$st');
      }),
    );
    return _ok({'opened': true});
  }

  static _R _closeSettingsSheet(
    String method,
    Map<String, String> params,
  ) async {
    final nav = DebugHooks.navigatorKey?.currentState;
    if (nav == null) return _error('navigator key not registered');
    return _ok({'closed': await nav.maybePop()});
  }

  static _R _playTrackByPath(String method, Map<String, String> params) async {
    final path = params['path'];
    if (path == null || path.isEmpty) return _error('path parameter required');
    final p = DebugHooks.provider as PlaybackController?;
    if (p == null) return _error('provider not registered');

    await p.playOneShot(AudioTrack(path: path, title: path.split('/').last));
    return _ok({'ok': true, 'path': path});
  }

  static _R _setPreference(String method, Map<String, String> params) async {
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

  static _R _clearPreference(String method, Map<String, String> params) async {
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

  /// Permissions requested by the QA-only library-permission probe.
  @visibleForTesting
  static const List<Permission> requestLibraryPermissionList = <Permission>[
    Permission.audio,
  ];

  static _R _requestLibraryPermission(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final results = await requestLibraryPermissionList.request();
      final granted = results[Permission.audio]?.isGranted ?? false;
      // Also drive the controller so its state updates.
      await (DebugHooks.libraryController as LibraryController?)
          ?.requestPermission();
      return _ok({
        'granted': granted,
        'audio': results[Permission.audio]?.name,
      });
    } catch (e) {
      return _error('requestLibraryPermission failed: $e');
    }
  }

  static _R _getOverflowReports(
    String method,
    Map<String, String> params,
  ) async {
    final clear = (params['clear'] ?? 'false') == 'true';
    final reports = _overflowReports
        .map<Map<String, Object?>>(Map<String, Object?>.from)
        .toList(growable: false);
    if (clear) _overflowReports.clear();
    return _ok({'reports': reports, 'count': reports.length});
  }

  static _R _screenshot(String method, Map<String, String> params) async {
    final pixelRatio = double.tryParse(params['pixelRatio'] ?? '') ?? 1.0;
    final renderObject = DebugHooks.screenshotBoundaryKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      return _error('screenshot boundary not mounted yet');
    }
    try {
      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final width = image.width;
      final height = image.height;
      image.dispose();
      if (png == null) return _error('toByteData returned null');
      return _ok({
        'png_base64': base64Encode(png.buffer.asUint8List()),
        'width': width,
        'height': height,
      });
    } catch (e) {
      return _error('screenshot failed: $e');
    }
  }

  /// Test-only handle on [_setSetting] (transport, screen, etc.).
  @visibleForTesting
  static Future<developer.ServiceExtensionResponse> debugSetSetting(
    Map<String, String> params,
  ) => _setSetting('debugSetSetting', params);

  /// Test-only handle on [_openSettingsSheet] (B-024 prompt-return assertion).
  @visibleForTesting
  static Future<developer.ServiceExtensionResponse> debugOpenSettingsSheet(
    Map<String, String> params,
  ) => _openSettingsSheet('debugOpenSettingsSheet', params);

  /// Test-only handle on [_tapByKey] (B-025 synthetic-tap dispatcher).
  @visibleForTesting
  static Future<developer.ServiceExtensionResponse> debugTapByKey(
    Map<String, String> params,
  ) => _tapByKey('debugTapByKey', params);

  /// Test-only handle on [_resolveScreenConfig] (B-023 per-skin resolution).
  @visibleForTesting
  static Future<ScreenConfig> resolveScreenConfig(ScreenType type) =>
      _resolveScreenConfig(type);
}
