// Unit tests covering the tooling fixes bundled in B-021..B-025
// (`lib/testing/agent_service.dart`). The agent extensions themselves
// are registered against the Dart VM service in debug mode; here we
// poke the underlying handlers through `@visibleForTesting` seams.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/models/transport_position.dart';
import 'package:nothingness/services/settings_service.dart';
import 'package:nothingness/testing/agent_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // SystemChrome calls inside SettingsService.setFullScreen et al.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall _) async => null,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // SettingsService is a singleton — reset its mutable notifiers so each
    // test starts from defaults.
    final s = SettingsService();
    s.screenConfigNotifier.value = SettingsService.defaultScreenConfig;
    s.transportPositionNotifier.value =
        SettingsService.defaultTransportPosition;
  });

  // ---------------------------------------------------------------------------
  // B-021: requestLibraryPermission must mirror the production OWN-mode
  // gate (audio only). Mic + storage in the side-channel produced
  // misleading 3-permission dialogs in QA.
  // ---------------------------------------------------------------------------
  group('B-021 requestLibraryPermissionList', () {
    test('contains only Permission.audio (no mic, no storage)', () {
      expect(AgentService.requestLibraryPermissionList,
          equals(const <Permission>[Permission.audio]));
      expect(
        AgentService.requestLibraryPermissionList,
        isNot(contains(Permission.microphone)),
      );
      expect(
        AgentService.requestLibraryPermissionList,
        isNot(contains(Permission.storage)),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // B-022: setSetting name=transport value=<top|bottom|off> routes through
  // SettingsService.setTransportPosition.
  // ---------------------------------------------------------------------------
  group('B-022 setSetting transport', () {
    test('value=top persists transport position as top', () async {
      final resp = await AgentService.debugSetSetting(
        const <String, String>{'name': 'transport', 'value': 'top'},
      );
      expect(resp.isError(), isFalse);
      expect(SettingsService().transportPositionNotifier.value,
          TransportPosition.top);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('transport_position'), 'top');
    });

    test('value=off persists transport position as off', () async {
      final resp = await AgentService.debugSetSetting(
        const <String, String>{'name': 'transport', 'value': 'off'},
      );
      expect(resp.isError(), isFalse);
      expect(SettingsService().transportPositionNotifier.value,
          TransportPosition.off);
    });

    test('unknown value reports an error', () async {
      final resp = await AgentService.debugSetSetting(
        const <String, String>{'name': 'transport', 'value': 'sideways'},
      );
      expect(resp.isError(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // B-023: setSetting name=screen value=dot must NOT clobber a persisted
  // DotScreenConfig.showSongInfo=true. It should reuse the persisted
  // config (via the same load path main.dart uses).
  // ---------------------------------------------------------------------------
  group('B-023 setSetting screen preserves per-skin config', () {
    test('persisted Dot showSongInfo=true survives a screen=dot hop',
        () async {
      const persistedDot = DotScreenConfig(showSongInfo: true);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'screen_config': jsonEncode(persistedDot.toJson()),
      });
      // Force the SettingsService notifier off-type so the resolver can't
      // shortcut to the live in-memory value.
      SettingsService().screenConfigNotifier.value =
          const SpectrumScreenConfig();

      final resp = await AgentService.debugSetSetting(
        const <String, String>{'name': 'screen', 'value': 'dot'},
      );
      expect(resp.isError(), isFalse);

      final active = SettingsService().screenConfigNotifier.value;
      expect(active, isA<DotScreenConfig>());
      expect((active as DotScreenConfig).showSongInfo, isTrue);
    });

    test('with no persisted config falls back to const default', () async {
      // No 'screen_config' key in mock prefs.
      SettingsService().screenConfigNotifier.value =
          const SpectrumScreenConfig();

      final resp = await AgentService.debugSetSetting(
        const <String, String>{'name': 'screen', 'value': 'dot'},
      );
      expect(resp.isError(), isFalse);
      final active = SettingsService().screenConfigNotifier.value;
      expect(active, isA<DotScreenConfig>());
      // Default showSongInfo is false.
      expect((active as DotScreenConfig).showSongInfo, isFalse);
    });

    test('live in-memory config of same type is reused as-is', () async {
      const live = DotScreenConfig(showSongInfo: true, maxDotSize: 200);
      SettingsService().screenConfigNotifier.value = live;

      final resp = await AgentService.debugSetSetting(
        const <String, String>{'name': 'screen', 'value': 'dot'},
      );
      expect(resp.isError(), isFalse);
      final active = SettingsService().screenConfigNotifier.value;
      expect(active, isA<DotScreenConfig>());
      expect((active as DotScreenConfig).showSongInfo, isTrue);
      expect(active.maxDotSize, 200);
    });
  });

  // ---------------------------------------------------------------------------
  // B-024: openSettingsSheet must return promptly. The previous impl
  // awaited Navigator.push, whose Future doesn't complete until the route
  // pops — RPC hung forever.
  // ---------------------------------------------------------------------------
  group('B-024 openSettingsSheet returns promptly', () {
    test('handler completes within 50ms even when opener never returns',
        () async {
      // Simulate the real opener (Navigator.push) by returning a Future
      // that NEVER completes.
      final neverPops = Completer<void>();
      AgentService.registerSettingsOpener(() => neverPops.future);

      try {
        final resp = await AgentService.debugOpenSettingsSheet(
          const <String, String>{},
        ).timeout(const Duration(milliseconds: 50));
        expect(resp.isError(), isFalse);
      } finally {
        AgentService.registerSettingsOpener(null);
        neverPops.complete(); // clean up the dangling Future.
      }
    });

    test('returns an error when no opener is registered', () async {
      AgentService.registerSettingsOpener(null);
      final resp = await AgentService.debugOpenSettingsSheet(
        const <String, String>{},
      );
      expect(resp.isError(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // B-025: tapByKey must fire `onTap` even when the GestureDetector is a
  // descendant of the keyed node. The fix dispatches a synthetic
  // PointerDown/PointerUp at the keyed widget's center via
  // GestureBinding.
  // ---------------------------------------------------------------------------
  group('B-025 tapByKey dispatches synthetic tap to descendant gesture',
      () {
    testWidgets('keyed parent → descendant GestureDetector receives onTap',
        (tester) async {
      const key = 'b025-descendant-gesture';
      var tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              // Keyed node carries the ValueKey but doesn't handle taps.
              child: SizedBox(
                key: const ValueKey<String>(key),
                width: 200,
                height: 200,
                child: Stack(
                  children: <Widget>[
                    // Gesture handler lives deep inside the subtree.
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => tapCount++,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final resp = await AgentService.debugTapByKey(
        const <String, String>{'key': key},
      );
      // Flush the gesture arena's microtask queue.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(resp.isError(), isFalse,
          reason: 'debugTapByKey returned error: ${resp.result}');
      expect(tapCount, 1,
          reason: 'descendant GestureDetector.onTap did not fire');
    });

    testWidgets('missing key returns an error', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final resp = await AgentService.debugTapByKey(
        const <String, String>{'key': 'no-such-key'},
      );
      expect(resp.isError(), isTrue);
    });
  });
}
