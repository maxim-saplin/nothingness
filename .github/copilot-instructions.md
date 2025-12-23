# Nothingness - GitHub Copilot Instructions

This is a Flutter media controller application. Consult the relevant rule files in `.cursor/rules/` when working in their domains.

## Rules Index

| Rule File | When to Consult |
|-----------|-----------------|
| `flutter-best-practices.mdc` | Writing/modifying Dart code. Covers linting, modern APIs, deprecations. |
| `testing-standards.mdc` | Adding features, models, services, widgets, screens. Covers test organization & mocking. |
| `documentation.mdc` | Adding architecture components or complex logic. Covers doc structure. |
| `flutter-commands.mdc` | Running Flutter CLI commands. Covers sandbox permissions. |
| `github-actions-polling.mdc` | Working with CI/CD workflows. Covers polling strategies & failure handling. |
| `rule-creation.mdc` | Creating/modifying rules in `.cursor/rules/`. Covers format & best practices. |

## Agent Behavior

1. **Context efficiency**: Don't load all rules—consult only those relevant to the current task
2. **Run validation**: Always run `flutter analyze` after Dart changes
3. **Reference docs**: Point to existing documentation rather than re-explaining
