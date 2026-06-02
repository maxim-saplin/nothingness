---
name: flutter-best-practices
description: Standards for code quality, linting, and modern API usage in Flutter. Use when writing or modifying Dart code. Covers deprecations and analyzer rules.
---
# Flutter Code Quality & Modernization

## 1. Run the Analyzer
After making substantive changes to Dart code, **ALWAYS** run `flutter analyze` to catch errors, warnings, and deprecations.
- Fix **ALL** reported issues before finishing the task.

## 2. Modern API Usage
Flutter evolves rapidly. You must be aware of and prefer modern language features and APIs over outdated ones, even if the analyzer doesn't strictly forbid the old ones yet.

**Common Deprecations to Watch:**
- Prefer `.withValues(alpha: ...)` over `.withOpacity(...)`.
- Prefer `.toARGB32()` over `.value` for Colors.
- Prefer `activeThumbColor` over `activeColor` in Switches.

## 3. General "Tendency to Produce Outdated Code"
LLMs often default to older patterns found in their training data.
- **Actively verify** if a standard pattern (like `WillPopScope`, `Opacity`, etc.) has a newer replacement (like `PopScope`, `withValues`).
- If `flutter analyze` flags a deprecation, treat it as an error to be fixed immediately.
