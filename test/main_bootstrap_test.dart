// Structural smoke test for `lib/main.dart` (B-008).
//
// Verifies that `runApp` is invoked synchronously: no `await` keyword may
// appear inside `main()` above the `runApp(` call. The splash-widget
// pattern depends on the engine getting a chance to render the first
// (cheap) frame before any heavy init runs; an `await` between `main`
// entry and `runApp` would defeat that and silently regress the cold
// launch cost we just clawed back.
//
// This is intentionally a string-level test rather than a widget test —
// cold-launch jank can only be measured against a live engine, but we
// can still pin the structural invariant cheaply in CI.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main() reaches runApp() with no awaits in between', () {
    final src = File('lib/main.dart').readAsStringSync();

    final mainStart = src.indexOf(RegExp(r'\bvoid\s+main\s*\(\s*\)\s*\{'));
    expect(
      mainStart,
      isNonNegative,
      reason: 'expected a `void main()` declaration in lib/main.dart',
    );

    final runAppIdx = src.indexOf('runApp(', mainStart);
    expect(
      runAppIdx,
      isNonNegative,
      reason: 'expected a runApp(...) call inside main()',
    );

    final prelude = src.substring(mainStart, runAppIdx);
    expect(
      RegExp(r'\bawait\b').hasMatch(prelude),
      isFalse,
      reason:
          'main() must reach runApp() synchronously so the splash widget '
          'gets a chance to paint a cheap first frame (B-008). Move any '
          'await into _BootstrapAppState.initState instead.',
    );

    // Also: the function should not be `Future<void> main()` — that would
    // mean Dart awaits it implicitly and async machinery runs before the
    // first frame.
    final futureMain = RegExp(
      r'\bFuture\s*<\s*void\s*>\s*main\s*\(\s*\)',
    ).hasMatch(src);
    expect(
      futureMain,
      isFalse,
      reason:
          'main() must be `void main()` (not `Future<void> main()`) so '
          'runApp runs in the same microtask as `main` entry (B-008).',
    );
  });
}
