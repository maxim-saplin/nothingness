import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nothingness/widgets/phone_frame.dart';

void main() {
  testWidgets('null frame passes the child through unchanged', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PhoneFrame(frame: null, child: Text('hi')),
      ),
    );
    expect(find.text('hi'), findsOneWidget);
    expect(find.byType(ColoredBox), findsNothing);
  });

  testWidgets('B-042: frame constrains child size and MediaQuery sees phone dims',
      (tester) async {
    // Desktop-sized surface; the frame should letterbox a 390x844 region.
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Size seenSize;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PhoneFrame(
          frame: const Size(390, 844),
          child: Builder(
            builder: (context) {
              seenSize = MediaQuery.sizeOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    // The child's MediaQuery reports phone dimensions, not the 1280x720 window.
    expect(seenSize, const Size(390, 844));

    // The child is physically constrained to the phone frame.
    final childBox = tester.getSize(find.byType(SizedBox).last);
    expect(childBox, const Size(390, 844));

    // Letterbox present.
    expect(find.byType(ColoredBox), findsOneWidget);
  });
}
