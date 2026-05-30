# Testing in Nothingness

This directory contains the test harness for the Nothingness project. We use a structured approach to testing to ensure reliability across models, services, and UI components.

## Directory Structure

We mirror the `lib/` directory structure to make tests easy to locate:

*   **`models/`**: Unit tests for data models (e.g., `SongInfo`). Focuses on JSON serialization/deserialization and data logic.
*   **`services/`**: Unit tests for services (e.g., `SettingsService`). We use mocking for external dependencies like `SharedPreferences` or Platform Channels.
*   **`widgets/`**: Widget tests for individual, reusable UI components.
*   **`screens/`**: Widget tests for full screens/pages. Focuses on verify page layout, navigation, and high-level user interactions.

## Running Tests

### Run All Tests
To run all tests in the project:
```bash
flutter test
```

### Run Specific Test File
To run a specific test file:
```bash
flutter test test/path/to/file_test.dart
```

## Tools & Libraries

*   **`flutter_test`**: The core Flutter testing framework.
*   **`mockito`**: Used for mocking dependencies (like platform channels or external services) to test units in isolation.
*   **`build_runner`**: Used to generate mock classes if utilizing code generation for mocks.
    *   Command to generate mocks: `dart run build_runner build`

## Writing New Tests

### Unit Tests (Models/Services)
*   **Goal**: Verify logic in isolation.
*   **Convention**: create a file named `<filename>_test.dart` in the corresponding `test/` subdirectory.
*   **Example**:
    ```dart
    test('should return default value on error', () {
      final result = myService.method();
      expect(result, defaultValue);
    });
    ```

### Widget Tests (Screens/Widgets)
*   **Goal**: Verify UI renders correctly and responds to user input.
*   **Convention**: Use `tester.pumpWidget()` to load the widget. Remember to wrap widgets in `MaterialApp` if they depend on Theme or Navigator.
*   **Example**:
    ```dart
    testWidgets('MyWidget renders title', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: MyWidget()));
      expect(find.text('Title'), findsOneWidget);
    });
    ```




## Async unit tests: wait for conditions, not wall-clock budgets

`flutter test` runs **one isolate per test file in parallel** (default
concurrency = CPU cores). Under that oversubscription a starved isolate's
timers fire late, so the classic pattern

```dart
someAsyncTrigger();
await Future.delayed(const Duration(milliseconds: 50)); // wall-clock budget
expect(controller.currentIndexNotifier.value, 2);       // may run too early → flaky
```

fails non-deterministically: the fixed delay can elapse before the async chain
settles. Use `test/support/pump_until.dart` instead — it returns as soon as a
condition holds (fast when idle) and tolerates a slow scheduler (parallel-safe):

```dart
import '../support/pump_until.dart';

someAsyncTrigger();
await pumpUntil(() => controller.currentIndexNotifier.value == 2);
expect(controller.currentIndexNotifier.value, 2);
```

Guidance:
*   **Positive ("reaches state") assertions** → `pumpUntil(condition)`. Wait on
    the *terminal* signal you assert on. Note the controller commits its index
    *before* `load()`/`play()`, so when a test asserts transport-level state
    (`transport.isPlaying`, `loadedPath`) under a `loadDelay`, include that in
    the condition: `pumpUntil(() => index == 2 && transport.isPlaying)`.
*   **Negative ("stays unchanged" / "event ignored") assertions** → keep a fixed
    settle delay. A late timer can't break a "no change" check, and the delay
    gives an *erroneous* change a chance to surface (see the B-036 regression and
    the interruption tests).
*   **Inherently time-based tests** (e.g. counting periodic-timer emissions over
    a window) stay on fixed delays — there is no single condition to await.
