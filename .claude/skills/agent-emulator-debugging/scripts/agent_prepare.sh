#!/usr/bin/env bash
# Prepare an Android emulator/device for agent-driven testing of nothingness:
#   1. Grant all runtime permissions (RECORD_AUDIO, READ_MEDIA_AUDIO,
#      READ_EXTERNAL_STORAGE, POST_NOTIFICATIONS) so first-launch UI doesn't
#      stall on the in-app "Permissions Required" overlay or OS dialogs.
#   2. (Optional) Stage one or more audio files from the host into the app's
#      private files dir, where SoLoud can open them reliably.
#
# Idempotent. Safe to run before or after install. Reports permissions it had
# to grant.
#
# Usage:
#   ./agent_prepare.sh --device <id>                       # just grant perms
#   ./agent_prepare.sh --device <id> --stage <host_file>   # grant + stage one file
#   ./agent_prepare.sh --device <id> --stage <f1> --stage <f2>
#
# Examples:
#   ./agent_prepare.sh --device emulator-5554
#   ./agent_prepare.sh -d emulator-5554 --stage .tmp/test_tone.wav
#
# After staging, the in-app path of `<host_file>` is:
#   /data/user/0/com.saplin.nothingness/files/$(basename <host_file>)
# Feed that to ext.nothingness.setQueue.

set -euo pipefail

PACKAGE="com.saplin.nothingness"

DEVICE=""
declare -a STAGE_FILES=()

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed -e 's/^# \{0,1\}//' -e '/^set -euo/d'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device) DEVICE="$2"; shift 2 ;;
    --stage)     STAGE_FILES+=("$2"); shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  echo "error: --device <id> required (e.g. emulator-5554)" >&2
  exit 2
fi

adb_d() { adb -s "$DEVICE" "$@"; }

if ! adb_d shell pm list packages | grep -q "^package:${PACKAGE}$"; then
  echo "error: $PACKAGE is not installed on $DEVICE. Run 'flutter run -d $DEVICE' first." >&2
  exit 1
fi

# --- 1. Grant runtime permissions -------------------------------------------
PERMS=(
  android.permission.RECORD_AUDIO
  android.permission.READ_MEDIA_AUDIO
  android.permission.READ_EXTERNAL_STORAGE
  android.permission.POST_NOTIFICATIONS
)

echo "Granting runtime permissions on $DEVICE..."
for perm in "${PERMS[@]}"; do
  # `pm grant` errors if the permission is not declared in the merged manifest;
  # swallow that case so the script stays cross-version-safe.
  if out=$(adb_d shell pm grant "$PACKAGE" "$perm" 2>&1); then
    echo "  + $perm"
  else
    echo "  - $perm (skipped: ${out//$'\r'/})"
  fi
done

# --- 2. Stage audio files (optional) ----------------------------------------
if (( ${#STAGE_FILES[@]} > 0 )); then
  echo "Staging ${#STAGE_FILES[@]} audio file(s) into $PACKAGE private files dir..."
  for host_path in "${STAGE_FILES[@]}"; do
    if [[ ! -f "$host_path" ]]; then
      echo "  ! missing: $host_path" >&2
      continue
    fi
    base=$(basename "$host_path")
    tmp_path="/data/local/tmp/$base"
    in_app_path="/data/user/0/${PACKAGE}/files/$base"

    adb_d push "$host_path" "$tmp_path" > /dev/null
    adb_d shell "run-as $PACKAGE cp '$tmp_path' files/" \
      || { echo "  ! run-as cp failed for $base" >&2; continue; }
    adb_d shell rm -f "$tmp_path" > /dev/null
    echo "  + $base  ->  $in_app_path"
  done
fi

echo "Done."
