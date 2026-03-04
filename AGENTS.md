# Nothingness - GitHub Copilot Instructions

This is a Flutter media controller application. Consult the relevant skills in `.claude/skills/` when working in their domains.

## Skills Index

| Skill | When to Consult |
|-------|-----------------|
| **flutter-best-practices** | Writing/modifying Dart code. Covers linting, modern APIs, deprecations. |
| **testing-standards** | Adding features, models, services, widgets, screens. Covers test organization & mocking. |
| **documentation** | Adding architecture components or complex logic. Covers doc structure. |
| **flutter-commands** | Running Flutter CLI commands. Covers sandbox permissions. |
| **github-actions-polling** | Working with CI/CD workflows. Covers polling strategies & failure handling. |
| **skill-creation** | Creating/modifying skills in `.claude/skills/`. Covers format & best practices. |
| **agent-emulator-debugging** | Driving the app on emulator via VM service extensions. Covers setup, state queries, actions. |

## Agent Behavior

1. **Context efficiency**: Don't load all rules—consult only those relevant to the current task
2. **Run validation**: Always run `flutter analyze` after Dart changes
3. **Reference docs**: Point to existing documentation rather than re-explaining

## WSL2 + Host Emulator

Use this workflow when code runs in WSL2 but the Android emulator runs on the Windows host.

1. Start host ADB server (Windows side):
	- `"/mnt/c/Users/<windows-user>/AppData/Local/Android/Sdk/platform-tools/adb.exe" -a start-server`
2. Run Flutter from WSL with ADB bridge + emulator ABI override:
	- `HOST_IP=$(ip route | awk '/default/ {print $3; exit}')`
	- `ADB_SERVER_SOCKET=tcp:${HOST_IP}:5037 CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554`
3. If you want launch-only (non-interactive terminal):
	- `ADB_SERVER_SOCKET=tcp:${HOST_IP}:5037 CI_EMULATOR_ABI=x86_64 flutter run -d emulator-5554 --no-resident`

## Temp Files

Store at local .tmp/ folder
