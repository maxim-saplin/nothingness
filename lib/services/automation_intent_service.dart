import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../providers/audio_player_provider.dart';

/// B-031: receives Android intent actions forwarded from `MainActivity` and
/// dispatches them against the in-app player.
///
/// Two delivery paths cover both warm- and cold-start:
///
/// 1. **Warm start** — `MainActivity.onNewIntent` calls
///    `onAutomationAction` on this side via the platform channel; we react
///    immediately.
/// 2. **Cold start** — the intent that launched the activity arrives before
///    [start] has wired the handler. Kotlin buffers it; we drain that
///    buffer once via `consumePendingAutomationAction` and dispatch.
///
/// Action tokens (Kotlin → Dart):
///   - `play`       — resume if paused (no-op if already playing).
///   - `pause`      — pause if playing (no-op if already paused).
///   - `playPause`  — unconditional toggle.
///
/// Mirrors the semantics of `ext.nothingness.play` / `ext.nothingness.pause`
/// in `lib/testing/agent_service.dart` so that the two automation surfaces
/// behave identically.
class AutomationIntentService {
  AutomationIntentService(
    this._provider, {
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.saplin.nothingness/automation';

  final AudioPlayerProvider _provider;
  final MethodChannel _channel;

  bool _started = false;

  /// Register the handler and drain any cold-start action. Idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAutomationAction') {
        final action = call.arguments;
        if (action is String) {
          await _dispatch(action);
        }
      }
      return null;
    });

    try {
      final pending =
          await _channel.invokeMethod<String?>('consumePendingAutomationAction');
      if (pending != null) {
        await _dispatch(pending);
      }
    } on PlatformException catch (e) {
      debugPrint('[AutomationIntentService] drain failed: $e');
    } on MissingPluginException {
      // Non-Android platforms or pre-B-031 native builds: no channel.
    }
  }

  Future<void> _dispatch(String action) async {
    switch (action) {
      case 'play':
        if (!_provider.isPlaying) await _provider.playPause();
        break;
      case 'pause':
        if (_provider.isPlaying) await _provider.playPause();
        break;
      case 'playPause':
        await _provider.playPause();
        break;
      default:
        debugPrint('[AutomationIntentService] unknown action: $action');
    }
  }
}
