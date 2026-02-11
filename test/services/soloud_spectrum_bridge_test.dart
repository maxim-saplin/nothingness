import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/spectrum_settings.dart';
import 'package:nothingness/services/soloud_spectrum_bridge.dart';

void main() {
  group('SoloudSpectrumBridge', () {
    late StreamController<List<double>> sourceController;
    late SoloudSpectrumBridge bridge;

    setUp(() {
      sourceController = StreamController<List<double>>.broadcast();
      bridge = SoloudSpectrumBridge(sourceStream: sourceController.stream);
    });

    tearDown(() async {
      await bridge.dispose();
      await sourceController.close();
    });

    test('forwards FFT data from source after start', () async {
      bridge.start();

      final completer = Completer<List<double>>();
      bridge.stream.first.then(completer.complete);

      sourceController.add([0.1, 0.2, 0.3]);
      final result = await completer.future;
      expect(result, [0.1, 0.2, 0.3]);
    });

    test('does not forward data before start', () async {
      final received = <List<double>>[];
      bridge.stream.listen(received.add);

      sourceController.add([0.5, 0.6]);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
    });

    test('stops forwarding after stop', () async {
      bridge.start();
      final received = <List<double>>[];
      bridge.stream.listen(received.add);

      sourceController.add([0.1]);
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));

      bridge.stop();
      sourceController.add([0.2]);
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
    });

    test('start is idempotent', () {
      bridge.start();
      bridge.start(); // should not throw or double-subscribe
      bridge.stop();
    });

    test('updateSettings stores settings', () {
      const settings = SpectrumSettings(noiseGateDb: -40.0);
      bridge.updateSettings(settings);
      expect(bridge.settings.noiseGateDb, -40.0);
    });
  });
}
