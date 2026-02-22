#!/usr/bin/env bash
set -euo pipefail

DEVICE="${DEVICE:-emulator-5554}"
PKG="${PKG:-com.saplin.nothingness}"
ACTIVITY="${ACTIVITY:-$PKG/.MainActivity}"
WINDOW_SEC="${WINDOW_SEC:-120}"
SAMPLE_SEC="${SAMPLE_SEC:-5}"
CI_MODE=false

usage() {
  cat <<'EOF'
Usage: tool/power/emulator_power_regression.sh [options]

Options:
  --device <id>        ADB device id (default: emulator-5554)
  --pkg <package>      Android package name (default: com.saplin.nothingness)
  --activity <name>    Launch activity (default: <pkg>/.MainActivity)
  --window-sec <n>     Sampling window in seconds (default: 120)
  --sample-sec <n>     Sampling interval in seconds (default: 5)
  --ci                 Enable CI-friendly strict exit behavior
  -h, --help           Show help

Examples:
  tool/power/emulator_power_regression.sh
  DEVICE=emulator-5554 PKG=com.saplin.nothingness tool/power/emulator_power_regression.sh --window-sec 180 --sample-sec 5
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --pkg)
      PKG="$2"
      shift 2
      ;;
    --activity)
      ACTIVITY="$2"
      shift 2
      ;;
    --window-sec)
      WINDOW_SEC="$2"
      shift 2
      ;;
    --sample-sec)
      SAMPLE_SEC="$2"
      shift 2
      ;;
    --ci)
      CI_MODE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 2
fi

if (( WINDOW_SEC <= 0 || SAMPLE_SEC <= 0 )); then
  echo "window/sample must be > 0" >&2
  exit 2
fi

SAMPLES=$(( WINDOW_SEC / SAMPLE_SEC ))
if (( SAMPLES <= 0 )); then
  echo "window must be >= sample interval" >&2
  exit 2
fi

adb -s "$DEVICE" get-state >/dev/null

if ! adb -s "$DEVICE" shell pm path "$PKG" | grep -q '^package:'; then
  echo "Package '$PKG' is not installed on $DEVICE" >&2
  echo "Install the app first or pass the correct --pkg value." >&2
  exit 2
fi

RUN_ID="$(date +%Y%m%d_%H%M%S)"
OUT_DIR=".tmp/power/${RUN_ID}-auto-regression"
mkdir -p "$OUT_DIR"

cat >"$OUT_DIR/meta.txt" <<EOF
run_id=$RUN_ID
device=$DEVICE
package=$PKG
activity=$ACTIVITY
window_sec=$WINDOW_SEC
sample_sec=$SAMPLE_SEC
samples=$SAMPLES
EOF

echo "[power] output: $OUT_DIR"

action_pkg_cpu_sample() {
  local phase="$1"
  local out_file="$2"

  echo "timestamp,phase,pkg_cpu_percent,raw" >"$out_file"

  for ((i=1; i<=SAMPLES; i++)); do
    local ts line pct raw
    ts="$(date +%H:%M:%S)"
    line="$(adb -s "$DEVICE" shell dumpsys cpuinfo | grep -i "$PKG" | head -n 1 || true)"

    if [[ -z "$line" ]]; then
      pct="0"
      raw="none"
    else
      pct="$(echo "$line" | sed -E 's/^[[:space:]]*\+?([0-9]+(\.[0-9]+)?)%.*/\1/' )"
      if [[ "$pct" == "$line" ]]; then
        pct="0"
      fi
      raw="$(echo "$line" | tr ',' ';')"
    fi

    echo "$ts,$phase,$pct,$raw" >>"$out_file"
    sleep "$SAMPLE_SEC"
  done
}

echo "[power] S0 control (force-stopped app)"
adb -s "$DEVICE" shell am force-stop "$PKG" || true
adb -s "$DEVICE" shell input keyevent KEYCODE_HOME || true
sleep 5
action_pkg_cpu_sample "s0_control" "$OUT_DIR/cpu_s0.csv"

echo "[power] S1 launch -> home -> idle"
adb -s "$DEVICE" logcat -c
adb -s "$DEVICE" shell am force-stop "$PKG" || true
START_OUT="$(adb -s "$DEVICE" shell am start -n "$ACTIVITY" 2>&1 || true)"
echo "$START_OUT" >"$OUT_DIR/am_start.txt"
if echo "$START_OUT" | grep -qiE 'Error type|does not exist|Exception'; then
  echo "Failed to launch activity '$ACTIVITY' for package '$PKG'" >&2
  echo "$START_OUT" >&2
  exit 2
fi
sleep 8
adb -s "$DEVICE" shell input keyevent KEYCODE_HOME
sleep 8
action_pkg_cpu_sample "s1_idle_bg" "$OUT_DIR/cpu_s1.csv"

adb -s "$DEVICE" shell pidof "$PKG" >"$OUT_DIR/pid.txt" || true
adb -s "$DEVICE" shell dumpsys cpuinfo >"$OUT_DIR/dumpsys_cpuinfo.txt"
adb -s "$DEVICE" shell dumpsys activity services "$PKG" >"$OUT_DIR/dumpsys_activity_services_pkg.txt"
adb -s "$DEVICE" shell dumpsys power >"$OUT_DIR/dumpsys_power.txt"
adb -s "$DEVICE" shell dumpsys jobscheduler >"$OUT_DIR/dumpsys_jobscheduler.txt"
adb -s "$DEVICE" shell dumpsys alarm >"$OUT_DIR/dumpsys_alarm.txt"
adb -s "$DEVICE" logcat -d -v time >"$OUT_DIR/logcat_s1.txt"

EVAL_ARGS=("$OUT_DIR" "--pkg" "$PKG")
if [[ "$CI_MODE" == true ]]; then
  EVAL_ARGS+=("--strict")
fi

python3 tool/power/evaluate_power_capture.py "${EVAL_ARGS[@]}"

echo "[power] done: $OUT_DIR"