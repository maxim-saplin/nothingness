import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/widgets/mid_ellipsis.dart';

/// Tests for [MidEllipsis] — the head-truncating widget used by the crumb
/// and browser rows. The name preserves the backlog entry (B-019); the
/// behaviour is head-truncate-keep-tail under LTR, native tail-ellipsis
/// under RTL.
void main() {
  // Use a monospace font so width math is predictable: each glyph is
  // (roughly) the same width as another at the same fontSize.
  const monoStyle = TextStyle(fontFamily: 'monospace', fontSize: 14);

  Widget wrap({required Widget child, TextDirection dir = TextDirection.ltr}) {
    return MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('short string that fits gets no ellipsis prefix', (tester) async {
    await tester.pumpWidget(
      wrap(
        child: const SizedBox(
          width: 400,
          child: MidEllipsis(text: 'hi', style: monoStyle),
        ),
      ),
    );

    expect(find.text('hi'), findsOneWidget);
    // No '…' prefix should appear anywhere in the rendered text.
    expect(find.textContaining('…'), findsNothing);
  });

  testWidgets('long string under tight width keeps the tail (LTR)', (
    tester,
  ) async {
    const original = '/storage/emulated/0/Music/Russian Rock';
    await tester.pumpWidget(
      wrap(
        child: const SizedBox(
          width: 80,
          child: MidEllipsis(text: original, style: monoStyle),
        ),
      ),
    );
    // Pump once more so the LayoutBuilder + measurement settles.
    await tester.pump();

    // Find the rendered Text and inspect its data.
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => s.contains('…'), orElse: () => '');

    expect(rendered.isNotEmpty, isTrue,
        reason: 'expected an ellipsised render of $original');
    expect(rendered.startsWith('…'), isTrue,
        reason: 'expected head-ellipsis prefix; got "$rendered"');
    // Tail of the original survives — e.g. 'Rock' (the meaningful end).
    expect(rendered.endsWith('Rock'), isTrue,
        reason: 'expected the meaningful tail to survive; got "$rendered"');
    // The rendered string is shorter than the original.
    expect(rendered.length < original.length, isTrue);
  });

  testWidgets('RTL falls back to native tail-ellipsis (keeps head)', (
    tester,
  ) async {
    const original = '/storage/emulated/0/Music/Russian Rock';
    await tester.pumpWidget(
      wrap(
        dir: TextDirection.rtl,
        child: const SizedBox(
          width: 80,
          child: MidEllipsis(text: original, style: monoStyle),
        ),
      ),
    );
    await tester.pump();

    // Under RTL we expect the framework's standard Text with tail-ellipsis,
    // so the rendered Text's data should be the original string verbatim
    // (Flutter handles the visual truncation via TextOverflow.ellipsis).
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => s == original, orElse: () => '');
    expect(rendered, original,
        reason: 'RTL path should leave the original string intact and rely '
            'on TextOverflow.ellipsis');
  });

  testWidgets('zero-width constraint does not throw', (tester) async {
    await tester.pumpWidget(
      wrap(
        child: const SizedBox(
          width: 0,
          child: MidEllipsis(
            text: 'something rather long here',
            style: monoStyle,
          ),
        ),
      ),
    );
    // If we got here without an exception, the widget survived the
    // pathological constraint. Take any error logged via tester.takeException.
    expect(tester.takeException(), isNull);
  });

  testWidgets('keepEnd cap shortens before width measurement', (tester) async {
    const original = '/very/long/path/that/keeps/going/Russian Rock';
    await tester.pumpWidget(
      wrap(
        child: const SizedBox(
          // Wide enough that width-truncation wouldn't kick in normally.
          width: 1000,
          child: MidEllipsis(
            text: original,
            style: monoStyle,
            keepEnd: 4,
          ),
        ),
      ),
    );
    await tester.pump();

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => s.contains('…'), orElse: () => '');
    expect(rendered, '…Rock');
  });
}
