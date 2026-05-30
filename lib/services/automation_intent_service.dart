import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../providers/audio_player_provider.dart';

/// B-031: receives Android intent actions from `MainActivity` and dispatches
/// them against the in-app player. Warm start arrives via `onAutomationAction`;
/// cold start is buffered by Kotlin and drained once via
/// `consumePendingAutomationAction`. Action tokens (`play` / `pause` /
/// `playPause`) mirror `ext.nothingness.*` in `dev/agent_service.dart`.
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
      // Non-Android or pre-B-031 native builds: no channel.
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
