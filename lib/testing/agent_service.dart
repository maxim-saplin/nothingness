import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/audio_track.dart';
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

  static bool _registered = false;

  /// Register all agent extensions. Safe to call multiple times (idempotent).
  static void register({required AudioPlayerProvider provider}) {
    if (!kDebugMode || _registered) return;

    _provider = provider;

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

    _registered = true;
    debugPrint('[AgentService] registered 11 VM service extensions');
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
      'androidSoloudDecoder': s.androidSoloudDecoderNotifier.value,
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
        'audioSource': s.settingsNotifier.value.audioSource.name,
        'noiseGateDb': s.settingsNotifier.value.noiseGateDb,
      },
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
      case 'androidSoloudDecoder':
        await s.setAndroidSoloudDecoder(value == 'true');
      case 'fullScreen':
        await s.setFullScreen(value == 'true');
      case 'debugLayout':
        s.debugLayoutNotifier.value = value == 'true';
      case 'useFilenameForMetadata':
        await s.setUseFilenameForMetadata(value == 'true');
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
        if (w is InkWell && w.onTap != null) {
          w.onTap!();
          tried = true;
          return;
        }
        el.visitChildren(visitChildren);
      }
      element.visitAncestorElements((ancestor) {
        if (tried) return false;
        final w = ancestor.widget;
        if (w is InkWell && w.onTap != null) {
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
}
