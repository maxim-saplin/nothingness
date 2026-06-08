#!/usr/bin/env bash
set -euo pipefail

DEVICE="${DEVICE:-emulator-5554}"
PKG="${PKG:-com.saplin.nothingness}"
ACTIVITY="${ACTIVITY:-$PKG/.MainActivity}"
WINDOW_SEC="${WINDOW_SEC:-120}"
SAMPLE_SEC="${SAMPLE_SEC:-5}"
CI_MODE=false
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEED_AUDIO="${SEED_AUDIO:-$ROOT_DIR/soloud/example/assets/audio/8_bit_mentality.mp3}"
APP_TRACK_PATH="/data/user/0/$PKG/files/8_bit_mentality.mp3"

usage() {
  cat <<'EOF'
Usage: tool/power/emulator_power_regression.sh [options]

Options:
  --device <id>        ADB device id (default: emulator-5554)
  --pkg <package>      Android package name (default: com.saplin.nothingness)
  --activity <name>    Launch activity (default: <pkg>/.MainActivity)
  --window-sec <n>     Sampling window in seconds (default: 120)
  --sample-sec <n>     Sampling interval in seconds (default: 5)
  --seed-audio <path>  Local audio file copied into app-private storage for the paused-restore scenario
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
    --seed-audio)
      SEED_AUDIO="$2"
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

if ! command -v dart >/dev/null 2>&1; then
  echo "dart is required" >&2
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

if [[ ! -f "$SEED_AUDIO" ]]; then
  echo "Seed audio '$SEED_AUDIO' does not exist" >&2
  exit 2
fi

seed_paused_restore_state() {
  local seed_dir="$OUT_DIR/seed_state"
  local remote_hive="/data/local/tmp/${PKG##*.}-power-seed-playlistbox.hive"
  local app_track_name
  local remote_audio

  app_track_name="$(basename "$APP_TRACK_PATH")"
  remote_audio="/data/local/tmp/${PKG##*.}-power-seed-${app_track_name}"

  rm -rf "$seed_dir"
  mkdir -p "$seed_dir"
  dart run "$ROOT_DIR/tool/power/seed_playlist.dart" "$seed_dir" "$APP_TRACK_PATH"

  adb -s "$DEVICE" push "$seed_dir/playlistbox.hive" "$remote_hive" >/dev/null
  adb -s "$DEVICE" push "$SEED_AUDIO" "$remote_audio" >/dev/null
  adb -s "$DEVICE" shell "run-as $PKG sh -c 'mkdir -p files app_flutter && cp $remote_audio files/$app_track_name && cp $remote_hive app_flutter/playlistbox.hive && : > app_flutter/playlistbox.lock'"
}

grant_runtime_permissions() {
  adb -s "$DEVICE" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  adb -s "$DEVICE" shell pm grant "$PKG" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
  adb -s "$DEVICE" shell pm grant "$PKG" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
  adb -s "$DEVICE" shell pm grant "$PKG" android.permission.RECORD_AUDIO >/dev/null 2>&1 || true
}

action_pkg_cpu_sample() {
  local phase="$1"
  local out_file="$2"
  local prev_total prev_proc prev_pids

  echo "timestamp,phase,pkg_cpu_percent,raw" >"$out_file"

  prev_total="$(adb -s "$DEVICE" shell cat /proc/stat | awk '/^cpu / {sum=0; for (i=2; i<=NF; i++) sum += $i; print sum; exit}' | tr -d '\r')"
  IFS='|' read -r prev_proc prev_pids < <(_pkg_cpu_snapshot)

  for ((i=1; i<=SAMPLES; i++)); do
    local ts curr_total curr_proc curr_pids pct raw total_delta proc_delta

    sleep "$SAMPLE_SEC"
    ts="$(date +%H:%M:%S)"
    curr_total="$(adb -s "$DEVICE" shell cat /proc/stat | awk '/^cpu / {sum=0; for (i=2; i<=NF; i++) sum += $i; print sum; exit}' | tr -d '\r')"
    IFS='|' read -r curr_proc curr_pids < <(_pkg_cpu_snapshot)

    total_delta=$(( curr_total - prev_total ))
    proc_delta=$(( curr_proc - prev_proc ))

    if (( total_delta <= 0 )); then
      pct="0"
      total_delta=0
      if (( proc_delta < 0 )); then
        proc_delta=0
      fi
    else
      if (( proc_delta < 0 )); then
        proc_delta=0
      fi
      pct="$(python3 - "$proc_delta" "$total_delta" <<'PY'
import sys
proc_delta = int(sys.argv[1])
total_delta = int(sys.argv[2])
if total_delta <= 0 or proc_delta <= 0:
    print("0")
else:
    value = (proc_delta * 100.0) / total_delta
    print(f"{value:.2f}".rstrip("0").rstrip("."))
PY
)"
    fi

    raw="pids=${curr_pids:-none};proc_jiffies_delta=${proc_delta};total_jiffies_delta=${total_delta}"
    echo "$ts,$phase,$pct,$raw" >>"$out_file"

    prev_total="$curr_total"
    prev_proc="$curr_proc"
    prev_pids="$curr_pids"
  done
}

_pkg_cpu_snapshot() {
  local pids proc_total stat pid

  pids="$(adb -s "$DEVICE" shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)"
  if [[ -z "$pids" ]]; then
    echo "0|none"
    return
  fi

  proc_total=0
  for pid in $pids; do
    stat="$(adb -s "$DEVICE" shell cat "/proc/$pid/stat" 2>/dev/null | tr -d '\r' || true)"
    if [[ -z "$stat" ]]; then
      continue
    fi
    proc_total=$(( proc_total + $(awk '{print $14 + $15}' <<<"$stat") ))
  done

  echo "$proc_total|$pids"
}

echo "[power] S0 control (force-stopped app)"
adb -s "$DEVICE" shell am force-stop "$PKG" || true
adb -s "$DEVICE" shell input keyevent KEYCODE_HOME || true
sleep 5
action_pkg_cpu_sample "s0_control" "$OUT_DIR/cpu_s0.csv"

echo "[power] S1 seeded paused restore -> home -> idle"
adb -s "$DEVICE" shell am force-stop "$PKG" || true
grant_runtime_permissions
seed_paused_restore_state
START_OUT="$(adb -s "$DEVICE" shell am start -n "$ACTIVITY" 2>&1 || true)"
echo "$START_OUT" >"$OUT_DIR/am_start.txt"
if echo "$START_OUT" | grep -qiE 'Error type|does not exist|Exception'; then
  echo "Failed to launch activity '$ACTIVITY' for package '$PKG'" >&2
  echo "$START_OUT" >&2
  exit 2
fi
sleep 8
adb -s "$DEVICE" shell am start -n "$ACTIVITY" -a "$PKG.action.PLAY" >/dev/null
sleep 4
adb -s "$DEVICE" shell am start -n "$ACTIVITY" -a "$PKG.action.PAUSE" >/dev/null
sleep 4
adb -s "$DEVICE" shell input keyevent KEYCODE_HOME
sleep 8

# Measure only the post-pause idle window. Resetting here removes historical
# batterystats entries from earlier runs and excludes the expected play/pause
# transition churn from the idle regression verdict.
adb -s "$DEVICE" shell dumpsys batterystats --reset >/dev/null
adb -s "$DEVICE" shell dumpsys batterystats enable full-history >/dev/null || true
adb -s "$DEVICE" shell dumpsys batterystats enable pretend-screen-off >/dev/null || true
adb -s "$DEVICE" logcat -c

action_pkg_cpu_sample "s1_idle_bg" "$OUT_DIR/cpu_s1.csv"

adb -s "$DEVICE" shell pidof "$PKG" >"$OUT_DIR/pid.txt" || true
adb -s "$DEVICE" shell dumpsys batterystats --checkin >"$OUT_DIR/batterystats_checkin.txt"
adb -s "$DEVICE" shell dumpsys batterystats --history >"$OUT_DIR/batterystats_history.txt"
adb -s "$DEVICE" shell dumpsys cpuinfo >"$OUT_DIR/dumpsys_cpuinfo.txt"
adb -s "$DEVICE" shell dumpsys activity services "$PKG" >"$OUT_DIR/dumpsys_activity_services_pkg.txt"
adb -s "$DEVICE" shell dumpsys media_session >"$OUT_DIR/dumpsys_media_session.txt"
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