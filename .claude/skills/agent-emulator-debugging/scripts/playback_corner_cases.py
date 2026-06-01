#!/usr/bin/env python3
"""Live playback corner-case harness — drives the running app via drive.py and
asserts state after each transition. Targets whatever DRIVE_TARGET points at
(linux | android). 25 assertions across 18 scenarios: latest-command-wins,
burst coalescing, queue exhaustion, prev/next semantics, interruptions,
one-shot, and missing-track skip.

Usage:
  # Linux desktop (files read from ./.tmp):
  DRIVE_TARGET=linux python3 .../playback_corner_cases.py
  # Android emulator/device (auto-stages fixtures into /Music + MediaStore):
  DRIVE_TARGET=android DRIVE_RUN_LOG=/tmp/flutter_run_android.log \
      python3 .../playback_corner_cases.py

On Android the app plays shared-storage tracks via a MediaStore content:// URI
(scoped storage blocks raw-path access — see lib/services/android_audio_source.dart),
so fixtures MUST be MediaStore-indexed. stage_android() pushes them and waits for
the index; an un-indexed push would spuriously fail every load.
"""
import json, os, subprocess, sys, time

D = ".claude/skills/agent-emulator-debugging/scripts/drive.py"
ENV = dict(os.environ)
ANDROID = ENV.get("DRIVE_TARGET") == "android"
M = "/storage/emulated/0/Music" if ANDROID else "/home/user/src/nothingness/.tmp"
ADB = ["adb"] + (["-s", ENV["ANDROID_SERIAL"]] if ENV.get("ANDROID_SERIAL") else [])

# Fixtures (must exist under ./.tmp locally). MISSING is intentionally absent.
FIXTURES = ["t1_a440_2s", "t2_c554_2s", "t3_e659_2s", "t4_g784_3s", "t5_a880_2s",
            "long_10s"]
T2 = [f"{M}/{n}.wav" for n in FIXTURES[:5]]
LONG = f"{M}/long_10s.wav"
MISSING = f"{M}/NOPE_does_not_exist.wav"

passed = failed = 0


def stage_android():
    """Push fixtures into shared storage and wait until MediaStore indexes them
    (content-URI resolution requires it). Idempotent."""
    print("=== staging fixtures into /Music + MediaStore ===")
    for n in FIXTURES:
        subprocess.run(ADB + ["push", f".tmp/{n}.wav", f"{M}/{n}.wav"],
                       capture_output=True, text=True)
    subprocess.run(ADB + ["shell", "rm", "-f", MISSING], capture_output=True)
    # Verify by listing audio _data and matching the path — avoids the brittle
    # device-side quoting of a `--where _data='...'` clause.
    for n in FIXTURES:
        path = f"{M}/{n}.wav"
        for _ in range(8):
            out = subprocess.run(
                ADB + ["shell", "content", "query",
                       "--uri", "content://media/external/audio/media",
                       "--projection", "_data"],
                capture_output=True, text=True).stdout
            if path in out:
                break
            time.sleep(1)
        else:
            print(f"  WARN  {n}.wav not indexed by MediaStore (load may fail)")


def call(method, **params):
    args = [D, "call", f"ext.nothingness.{method}"] + [f"{k}={v}" for k, v in params.items()]
    try:
        out = subprocess.run(args, env=ENV, capture_output=True, text=True, timeout=30).stdout
        return json.loads(out) if out.strip().startswith("{") else {}
    except Exception as e:
        return {"_err": str(e)}


def state():
    return call("getPlaybackState")


def diag():
    return call("getDiagnostics").get("snapshot", {})


def setq(paths, **kw):
    call("setQueue", paths=",".join(paths), **kw)


def wait_until(pred, timeout=4.0):
    end = time.time() + timeout
    while time.time() < end:
        if pred(state()):
            return True
        time.sleep(0.15)
    return False


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1; print(f"  PASS  {name}")
    else:
        failed += 1; print(f"  FAIL  {name}  -- {detail}")


def hdr(t): print(f"\n=== {t} ===")


if ANDROID:
    stage_android()

# 1. single track plays
hdr("single track plays")
setq([T2[0]]); call("play")
ok = wait_until(lambda s: s.get("isPlaying") and s.get("spectrumNonZero"))
check("single track playing", ok, state())

# 2. multi: next advances and plays (long tracks: no real-time auto-advance)
hdr("next advances + plays")
setq([LONG, LONG, LONG]); call("play"); time.sleep(0.4)
call("next")
ok = wait_until(lambda s: s.get("currentIndex") == 1 and s.get("isPlaying"))
check("next -> idx1 playing", ok, state())

# 3. next at tail does not wrap
hdr("next at tail no wrap")
setq([LONG, LONG]); call("play"); call("next"); time.sleep(0.3)
call("next"); call("next"); time.sleep(0.4)
s = state(); check("stays at tail idx1", s.get("currentIndex") == 1, s)

# 4. pause then play resumes (same idx)
hdr("pause -> play resumes")
setq([LONG]); call("play"); time.sleep(0.5)
call("pause"); ok1 = wait_until(lambda s: not s.get("isPlaying"))
call("play"); ok2 = wait_until(lambda s: s.get("isPlaying") and s.get("currentIndex") == 0)
check("pause stops", ok1); check("play resumes idx0", ok2, state())

# 5. latest-wins: pause; next; play -> playing next
hdr("latest-wins pause;next;play -> PLAYING")
setq([LONG, LONG, LONG]); call("play"); time.sleep(0.5)
call("pause"); call("next"); call("play")
ok = wait_until(lambda s: s.get("isPlaying"), 5)
check("ends PLAYING", ok, state())

# 6. latest-wins: play; next; pause -> paused
hdr("latest-wins play;next;pause -> PAUSED")
setq([LONG, LONG, LONG]); call("play"); time.sleep(0.5)
call("play"); call("next"); call("pause")
ok = wait_until(lambda s: not s.get("isPlaying"), 5)
check("ends PAUSED", ok, state())

# 7. rapid burst advances per tap, plays landed (long tracks avoid end-races)
hdr("rapid 5x next -> idx5 playing")
setq([LONG, LONG, LONG, LONG, LONG, LONG]); call("play"); time.sleep(0.5)
for _ in range(5):
    subprocess.Popen([D, "next"], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ok = wait_until(lambda s: s.get("currentIndex") == 5 and s.get("isPlaying"), 6)
check("burst -> idx5 playing", ok, state())

# 8. natural end of single-track queue -> stop + intent pause; play restarts
hdr("single-track natural end -> play restarts")
setq([T2[0]]); call("play")  # 2s track
time.sleep(3)  # let it end
s = state(); d = diag()
check("stopped after end", not s.get("isPlaying"), s)
check("intent reset to pause", d.get("userIntent") == "pause", d)
call("play"); ok = wait_until(lambda s: s.get("isPlaying"), 3)
check("play restarts after end", ok, state())

# 9. previous within 3s STEPS BACK (standard player behavior)
hdr("previous within 3s steps back")
setq([LONG, LONG]); call("play"); call("next"); time.sleep(0.6)
call("prev")  # <3s into idx1 -> step back to idx0
ok = wait_until(lambda s: s.get("currentIndex") == 0 and s.get("isPlaying"))
check("prev <3s -> idx0 (step back)", ok, state())

# 10. previous at head
hdr("previous at head")
setq([LONG, LONG]); call("play"); time.sleep(0.5)
call("prev"); time.sleep(0.6)
s = state(); check("prev at head -> idx0 playing", s.get("currentIndex") == 0 and s.get("isPlaying"), s)

# 11. missing track is skipped
hdr("missing track skipped")
setq([MISSING, T2[1]]); call("play")
ok = wait_until(lambda s: s.get("currentIndex") == 1 and s.get("isPlaying"), 5)
check("skips missing -> idx1 playing", ok, state())

# 12. interruption begin pauses, end resumes
hdr("interruption pause/resume")
setq([LONG]); call("play"); time.sleep(0.6)
call("simulateInterruption", phase="begin", kind="pause")
ok1 = wait_until(lambda s: not s.get("isPlaying"))
call("simulateInterruption", phase="end", kind="pause")
ok2 = wait_until(lambda s: s.get("isPlaying"))
check("interruption pauses", ok1, state()); check("resumes after", ok2, state())

# 13. becoming noisy pauses, no resume
hdr("becoming noisy -> pause, no auto-resume")
setq([LONG]); call("play"); time.sleep(0.6)
call("simulateNoisy")
ok = wait_until(lambda s: not s.get("isPlaying"))
check("noisy pauses", ok, state())

# 14. previous steps back to earlier track (from a freshly-loaded track, pos~0)
hdr("previous steps back")
setq([LONG, LONG, LONG]); call("play"); call("next"); call("next"); time.sleep(0.6)
call("prev"); time.sleep(0.6)
s = state(); check("prev keeps playing valid idx", s.get("isPlaying") and 0 <= s.get("currentIndex", -1) <= 2, s)

# 15. next while PAUSED -> advances and plays (nav implies play)
hdr("next while paused -> plays")
setq([LONG, LONG, LONG]); call("play"); time.sleep(0.4)
call("pause"); wait_until(lambda s: not s.get("isPlaying"))
call("next")
ok = wait_until(lambda s: s.get("isPlaying") and s.get("currentIndex") == 1, 4)
check("next from paused -> idx1 playing", ok, state())

# 16. concurrent pause/play spam settles deterministically
hdr("pause/play spam settles")
setq([LONG]); call("play"); time.sleep(0.4)
for m in ["pause", "play", "pause", "play", "pause", "play"]:
    call(m)
ok = wait_until(lambda s: s.get("isPlaying"), 4)
check("spam ending in play -> playing", ok, state())
for m in ["play", "pause", "play", "pause"]:
    call(m)
ok = wait_until(lambda s: not s.get("isPlaying"), 4)
check("spam ending in pause -> paused", ok, state())

# 17. one-shot then next exits one-shot back to queue
hdr("one-shot play, then next exits")
setq([T2[0], T2[1], T2[2]]); call("play"); time.sleep(0.4)
call("playTrackByPath", path=LONG)
ok = wait_until(lambda s: s.get("isPlaying"), 4)
check("one-shot plays", ok, state())
call("next"); time.sleep(0.8)
s = state(); check("next after one-shot keeps playing", s.get("isPlaying"), s)

# 18. exhaust queue then play (the regression) + next afterwards
hdr("exhaust queue -> play -> next")
setq([T2[0], T2[1]]); call("play"); time.sleep(6)  # both 2s tracks end
d = diag(); check("exhausted intent=pause", d.get("userIntent") == "pause", d)
call("play"); ok = wait_until(lambda s: s.get("isPlaying"), 3)
check("play after exhaust restarts", ok, state())

print(f"\n==== RESULT: {passed} passed, {failed} failed ====")
sys.exit(1 if failed else 0)
