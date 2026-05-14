import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/models/screen_config.dart';
import 'package:nothingness/widgets/heroes/dot_hero.dart';

import '_test_helpers.dart';

void main() {
  testWidgets('dot grows when bass energy is high', (tester) async {
    final provider = FakeAudioPlayerProvider(
      spectrumData: List<double>.filled(8, 0.0),
    );
    const config = DotScreenConfig();

    await tester.pumpWidget(
      wrapWithProvider(
        provider,
        const SizedBox(
          width: 400,
          height: 400,
          child: DotHero(config: config),
        ),
      ),
    );

    Size dotSizeFor(WidgetTester tester) {
      // The dot is the inner Container (last in the tree under the outer
      // background-coloured Container).
      final inner = find.descendant(
        of: find.byType(DotHero),
        matching: find.byType(Container),
      );
      // Outer fills, inner = circle. Pick the smaller one.
      final outerSize = tester.getSize(inner.first);
      final innerSize = tester.getSize(inner.last);
      return innerSize.width < outerSize.width ? innerSize : outerSize;
    }

    final smallSize = dotSizeFor(tester);

    provider.setSpectrum(List<double>.filled(8, 1.0));
    await tester.pump();

    final bigSize = dotSizeFor(tester);
    expect(bigSize.width, greaterThan(smallSize.width));
  });
}
