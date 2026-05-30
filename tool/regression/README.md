# Regression replay scripts

`drive.py replay <file>` runs each line as a `drive.py` invocation (blank lines
and `#` comments skipped; aborts on the first non-zero exit). These scripts
*drive* the app and dump state/screenshots — read the output (and the PNGs in
`.tmp/agent_shots/`) to judge pass/fail; `replay` itself does not assert.

```bash
export DRIVE_TARGET=linux   # or android
D=.claude/skills/agent-emulator-debugging/scripts/drive.py
$D replay tool/regression/smoke.txt
```

Scripts that need audio assume short test tones staged under `.tmp/` (generate
with the snippet in `docs/regression-testing-playbook.md` / prior sessions, or
`adb push` on Android). UI/state/layout scripts need no audio.

See `docs/regression-testing-playbook.md` for the full test table these cover.
