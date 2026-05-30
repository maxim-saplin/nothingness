import 'dart:async';

/// Waits until [condition] returns true, re-checking on a short [interval] up
/// to [timeout], then returns.
///
/// This replaces the fragile `await Future.delayed(fixedBudget)` + `expect`
/// pattern in async unit tests. A fixed delay asserts on a wall-clock budget,
/// so when the test isolate is starved under parallel load (`flutter test`
/// runs one isolate per file, default concurrency = CPU cores) its timers fire
/// late and the assertion can run before the async chain has settled —
/// producing non-deterministic failures.
///
/// `pumpUntil` instead returns *as soon as* the condition holds (fast when the
/// event loop is idle) and tolerates a slow scheduler (it just polls longer),
/// so the same test is both quick and parallel-safe.
///
/// It deliberately does **not** throw on timeout — it returns and lets the
/// following `expect(...)` produce the meaningful, value-bearing failure
/// message. The [timeout] is a generous upper bound, not the expected wait.
Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (!DateTime.now().isBefore(deadline)) return;
    await Future<void>.delayed(interval);
  }
}
