from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

RUNTIME = Path("/run/nothingness")
PROCESSES: list[subprocess.Popen[object]] = []
STOPPING = False


def start(args: list[str], log_name: str) -> subprocess.Popen[object]:
    log = (RUNTIME / "logs" / log_name).open("w")
    process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
    PROCESSES.append(process)
    return process


def write_health(value: dict[str, object], stream: object = sys.stdout) -> None:
    content = json.dumps(value, separators=(",", ":"))
    (RUNTIME / "health.json").write_text(content + "\n")
    print(content, file=stream)


def shutdown(_signum: int, _frame: object) -> None:
    global STOPPING
    STOPPING = True
    for process in PROCESSES:
        if process.poll() is None:
            process.terminate()


def main() -> int:
    home = Path(os.environ["HOME"])
    RUNTIME.mkdir(parents=True, exist_ok=True)
    RUNTIME.chmod(0o700)
    directories = [home, Path(os.environ["XDG_CONFIG_HOME"]), Path(os.environ["XDG_DATA_HOME"]), Path(os.environ["PI_CODING_AGENT_DIR"]), RUNTIME / "logs", RUNTIME / "drive", Path("/workspace")]
    for directory in directories:
        directory.mkdir(parents=True, exist_ok=True)
    for directory in directories[:4]:
        directory.chmod(0o700)
    subprocess.run(["xdg-user-dirs-update"], env=os.environ.copy(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    pulse_runtime = RUNTIME / "pulse"
    pulse_runtime.mkdir(exist_ok=True)
    pulse_runtime.chmod(0o700)
    os.environ.update({"PULSE_SERVER": f"unix:{pulse_runtime}/native", "XDG_RUNTIME_DIR": str(RUNTIME), "DRIVE_RUN_LOG": str(RUNTIME / "drive" / "flutter_run.log"), "DRIVE_FLUTTER_FIFO": str(RUNTIME / "drive" / "flutter_input"), "DRIVE_WS_CACHE": str(RUNTIME / "drive" / "vm_ws.txt")})
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    write_health({"status": "starting", "display": os.environ["DISPLAY"]})
    xvfb = start(["Xvfb", os.environ["DISPLAY"], "-screen", "0", "1280x800x24", "-ac", "+extension", "GLX", "+render", "-noreset"], "xvfb.log")
    openbox = start(["openbox"], "openbox.log")
    x11vnc = start(["x11vnc", "-display", os.environ["DISPLAY"], "-forever", "-shared", "-nopw", "-rfbport", "5900"], "x11vnc.log")
    novnc = start(["websockify", "--web=/usr/share/novnc/", "6080", "localhost:5900"], "novnc.log")
    with (RUNTIME / "logs" / "pulseaudio.log").open("w") as output:
        if subprocess.run(["pulseaudio", "--daemonize=yes", "--exit-idle-time=-1", f"--log-target=file:{RUNTIME / 'logs' / 'pulseaudio.log'}"], stdout=output, stderr=subprocess.STDOUT).returncode:
            write_health({"status": "failed", "reason": "desktop_startup_failed"}, sys.stderr)
            return 70
    # Keep retrying until Pulse answers or SIGTERM. A fixed 30s budget raced
    # workspace copy on cold starts: the entrypoint exited, `--rm` deleted the
    # container, and every outer waiter burned its full poll budget on a ghost.
    while not STOPPING:
        if all(process.poll() is None for process in (xvfb, x11vnc, novnc)) and subprocess.run(["pactl", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            write_health({"status": "ready", "display": os.environ["DISPLAY"], "media": "/opt/nothingness/media", "workspace": "/workspace", "pids": {"xvfb": xvfb.pid, "openbox": openbox.pid, "x11vnc": x11vnc.pid, "novnc": novnc.pid}})
            while not STOPPING:
                time.sleep(1)
            return 0
        time.sleep(1)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    finally:
        shutdown(0, None)
