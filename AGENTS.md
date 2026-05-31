# Nothingness

This is a Flutter media controller application

## Agent Behavior

1. **Context efficiency**: Don't load all rules—consult only those relevant to the current task
2. **Run validation**: Always run `flutter analyze` after Dart changes
3. **Reference docs**: Point to existing documentation rather than re-explaining

## Simplicity & No Bloat

The default bias is *less code*. SLOC is a north-star metric (see `goal-sloc` skill) — a smaller, clearer solution beats a clever or defensive one.

- **Fix at the right layer, once.** Push a fix to its source so the rest of the system stays dumb. Never re-implement logic that already exists — reuse it (e.g. parse a filename with the one parser, don't add a second stripper in the UI).
- **Comments earn their place.** Code should be self-descriptive; names carry the *what*. Write a comment only for the *why* that the code can't show — a non-obvious constraint, a platform quirk, a tracked-issue rationale. Delete comments that restate the line below them.
- **No speculative flexibility.** Don't add parameters, abstractions, or branches for cases no caller needs today.
- **Prefer deleting.** When changing behaviour, remove the code it replaces rather than layering new code on top.

### WSL2 + Host Emulator

Precondition: WSL2 mirrored networking must be configured. If `adb devices` shows nothing, run `/wsl2-adb-setup` skill.

Once configured, plain `adb` works from WSL2 with no bridge or shims needed.

## Python Tooling

Python scripts (e.g. `drive.py`) are managed by `uv` against a repo-root `.venv`. Bootstrap once after checkout with `uv sync`. Deps are declared in `pyproject.toml`; `drive.py` also carries a PEP 723 inline header so it self-installs on first run.

## Temp Files

Store at local .tmp/ folder
