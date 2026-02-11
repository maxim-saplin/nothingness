---
name: flutter-commands
description: Guidelines for running Flutter CLI commands and handling sandbox permissions. Use when executing flutter build, run, pub, or clean commands.
---
# Flutter Command Execution

When running `flutter` commands via terminal tools, be aware of sandbox restrictions.

## Permissions

The Flutter SDK often attempts to write to its own installation directory (outside the workspace) to update caches, timestamps (e.g., `engine.stamp`), or download artifacts during build processes.

**Rule:** Always request full permissions when running `flutter` commands that invoke the build system, package management, or device interaction.

Examples of commands requiring full permissions:
- `flutter build ...` (apk, ios, macos, web, etc.)
- `flutter run`
- `flutter pub get` / `flutter pub upgrade` (if it triggers SDK updates/downloads)
- `flutter clean`

## Error Handling

If you encounter an "Operation not permitted" error related to paths outside the workspace (e.g., inside `/Users/.../flutter/`), it is a sandbox violation. Retry the command with full permissions.
