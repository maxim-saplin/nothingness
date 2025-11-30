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

