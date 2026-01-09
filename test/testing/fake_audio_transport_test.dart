import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/services/audio_transport.dart';
import 'package:nothingness/testing/fake_audio_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FakeAudioTransport: load success emits LoadedEvent and does not throw', () async {
    final t = FakeAudioTransport();

    final events = <TransportEvent>[];
    final sub = t.eventStream.listen(events.add);

    await t.init();
    await t.load('/ok.mp3');
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<TransportLoadedEvent>().length, 1);
    expect((events.whereType<TransportLoadedEvent>().single).path, '/ok.mp3');

    await sub.cancel();
    await t.dispose();
  });

  test('FakeAudioTransport: load notFound emits ErrorEvent and throws', () async {
    final t = FakeAudioTransport(
      outcomesByPath: {'/missing.mp3': const FakeLoadOutcome.notFound()},
    );

    final events = <TransportEvent>[];
    final sub = t.eventStream.listen(events.add);

    await t.init();
    await expectLater(() => t.load('/missing.mp3'), throwsStateError);
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<TransportErrorEvent>().length, 1);
    final e = events.whereType<TransportErrorEvent>().single;
    expect(e.path, '/missing.mp3');

    await sub.cancel();
    await t.dispose();
  });

  test('FakeAudioTransport: emitEnded emits EndedEvent for current path', () async {
    final t = FakeAudioTransport();

    final events = <TransportEvent>[];
    final sub = t.eventStream.listen(events.add);

    await t.init();
    await t.load('/a.mp3');
    t.emitEnded();
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<TransportEndedEvent>().length, 1);
    expect(events.whereType<TransportEndedEvent>().single.path, '/a.mp3');

    await sub.cancel();
    await t.dispose();
  });

  test('FakeAudioTransport: seek emits PositionEvent', () async {
    final t = FakeAudioTransport();

    final events = <TransportEvent>[];
    final sub = t.eventStream.listen(events.add);

    await t.init();
    await t.seek(const Duration(milliseconds: 123));
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<TransportPositionEvent>().length, 1);
    expect(
      events.whereType<TransportPositionEvent>().single.position,
      const Duration(milliseconds: 123),
    );

    await sub.cancel();
    await t.dispose();
  });
}

