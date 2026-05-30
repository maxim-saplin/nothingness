#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["websockets>=12.0"]
# ///
"""drive.py — CLI driver for the Nothingness app's VM service surface.

Wraps `ext.nothingness.*` extensions exposed by `lib/testing/agent_service.dart`
so a human or agent can puppet the live app without writing one-off scripts.

Targets:
  - **android** (default) — drives an emulator/device through `adb`.
  - **linux** / **macos** — drives a Flutter desktop build of the app. ADB
    is bypassed; the VM service URI is read from `/tmp/flutter_run.log` and
    `shoot` rasterizes via `ext.nothingness.screenshot` (no `adb screencap`).

The target is picked from `--target` / `DRIVE_TARGET`; if neither is set
drive.py sniffs `/tmp/flutter_run.log` ("...on Linux in debug mode") and
falls back to `android`.

Subcommands print structured JSON on stdout and exit 0 on success, non-zero on
RPC error.

Usage (a few examples):
  drive.py inspect                       # router + library + playback + overflow
  drive.py screen void                   # set the active home screen
  drive.py variant dark                  # dark / light / system
  drive.py mode own                      # own / background
  drive.py nav /storage/emulated/0/Music # navigate Void to a path
  drive.py up                            # navigateVoidUp
  drive.py settings open|close
  drive.py play /absolute/path/foo.mp3
  drive.py pause | resume | next | prev
  drive.py pref void_hint_shown=false:bool
  drive.py clearpref void_hint_shown
  drive.py permit                        # request library permissions
  drive.py shoot before_b001             # PNG -> .tmp/agent_shots/before_b001.png
  drive.py tree [depth]
  drive.py tap <key>
  drive.py logcat [lines]                # desktop: tails /tmp/flutter_run.log
  drive.py overflows [--clear]
  drive.py reset                         # Android only; on desktop, restart `flutter run`
  drive.py replay <script.txt>           # newline-separated drive.py invocations
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import websockets


REPO_ROOT = Path(__file__).resolve().parents[4]
SHOTS_DIR = REPO_ROOT / ".tmp" / "agent_shots"
SHOTS_DIR.mkdir(parents=True, exist_ok=True)

DEFAULT_SERIAL = os.environ.get("ADB_SERIAL", "emulator-5554")
APP_ID = "com.saplin.nothingness"
LAUNCH_ACTIVITY = "com.saplin.nothingness.MainActivity"
LOCAL_FORWARD_PORT = int(os.environ.get("DRIVE_LOCAL_PORT", "8181"))

# Where we cache the discovered VM service WebSocket URI between runs.
WS_CACHE = Path(__file__).with_name(".vm_ws.txt")

# The `flutter run` stdout log to scan for the host-local VM/DDS URI. Override
# with DRIVE_RUN_LOG when running a second session (e.g. an Android run logging
# to /tmp/flutter_run_android.log while a Linux session owns the default path).
FLUTTER_RUN_LOG = Path(os.environ.get("DRIVE_RUN_LOG", "/tmp/flutter_run.log"))

# Valid `flutter run -d <id>` targets we know how to drive. "android" covers
# any adb-attached device; "linux" / "macos" cover Flutter desktop builds.
TARGETS = ("android", "linux", "macos")


def _resolve_target() -> str:
    """Pick the active target: explicit env var first, then sniff the running
    `flutter run` log, then default to `android` for backward compatibility."""
    env = os.environ.get("DRIVE_TARGET", "").strip().lower()
    if env in TARGETS:
        return env
    if FLUTTER_RUN_LOG.exists():
        try:
            text = FLUTTER_RUN_LOG.read_text(errors="ignore")[:4000]
        except OSError:
            text = ""
        # `flutter run` prints "Launching lib/main.dart on Linux in debug mode"
        # at boot — match the device name to map back to our target enum.
        m = re.search(r"on\s+(Linux|macOS|Android|.*Android.*)\s+in\s+debug", text, re.I)
        if m:
            dev = m.group(1).lower()
            if "linux" in dev:
                return "linux"
            if "macos" in dev or "darwin" in dev:
                return "macos"
            return "android"
    return "android"


TARGET = _resolve_target()
IS_DESKTOP = TARGET in ("linux", "macos")


# ---------------------------------------------------------------------------
# adb helpers
# ---------------------------------------------------------------------------

def adb(*args: str, serial: str = DEFAULT_SERIAL, check: bool = True,
        capture: bool = True, timeout: float | None = 30) -> subprocess.CompletedProcess:
    cmd = ["adb", "-s", serial, *args]
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture,
        text=True,
        timeout=timeout,
    )


# ---------------------------------------------------------------------------
# VM service discovery
# ---------------------------------------------------------------------------

VM_PATTERNS = [
    # `The Dart VM service is listening on http://127.0.0.1:33891/AbCdEf=/`
    re.compile(r"Dart VM service.*?listening on (http://[^\s/]+/[A-Za-z0-9_=\-]+/?)"),
    # Older Flutter emits a different prefix; keep a backup pattern.
    re.compile(r"Observatory.*?listening on (http://[^\s/]+/[A-Za-z0-9_=\-]+/?)"),
    # `A Dart VM Service on Android SDK ...: http://127.0.0.1:PORT/TOKEN=/`
    re.compile(r"A Dart VM Service .*?:\s+(http://[^\s/]+/[A-Za-z0-9_=\-]+/?)")
]


def _scan_logcat_for_vm_uri(serial: str, max_lines: int = 5000) -> str | None:
    """Return the most recent VM service URI seen in logcat, or None."""
    proc = adb("logcat", "-d", "-v", "brief", "-t", str(max_lines), serial=serial)
    found = None
    for line in proc.stdout.splitlines():
        for pat in VM_PATTERNS:
            m = pat.search(line)
            if m:
                found = m.group(1)
    return found


def _parse_vm_uri(uri: str) -> tuple[int, str]:
    """Return (remote_port, auth_token) from a Dart VM service URI."""
    # uri looks like http://127.0.0.1:33891/<token>/
    m = re.match(r"http://[^:]+:(\d+)/([^/]+)/?", uri)
    if not m:
        raise RuntimeError(f"cannot parse VM service URI: {uri!r}")
    return int(m.group(1)), m.group(2)


def _forward_port(remote_port: int, serial: str = DEFAULT_SERIAL) -> int:
    """Set up adb port forwarding to expose the device's VM service locally."""
    adb("forward", f"tcp:{LOCAL_FORWARD_PORT}", f"tcp:{remote_port}", serial=serial)
    return LOCAL_FORWARD_PORT


def _ws_uri(local_port: int, token: str) -> str:
    return f"ws://127.0.0.1:{local_port}/{token}/ws"


def _scan_flutter_run_log_for_vm_uri() -> str | None:
    """If `flutter run` is active, extract the host-side VM service URI from
    its stdout log. Flutter forwards the device port automatically so this
    URI is already local — no adb forward needed."""
    if not FLUTTER_RUN_LOG.exists():
        return None
    try:
        text = FLUTTER_RUN_LOG.read_text(errors="ignore")
    except Exception:
        return None
    found = None
    for pat in VM_PATTERNS:
        for m in pat.finditer(text):
            found = m.group(1)
    return found


def _resolve_ws(serial: str = DEFAULT_SERIAL, force: bool = False) -> str:
    """Discover (or load cached) WebSocket URI.

    On Android, sets up an adb port forward when only logcat exposes the URI.
    On desktop (linux/macos), `flutter run` always logs a local 127.0.0.1
    URI directly, so the adb path is skipped entirely.
    """
    if not force and WS_CACHE.exists():
        cached = WS_CACHE.read_text().strip()
        if cached:
            try:
                m = re.match(r"ws://127\.0\.0\.1:(\d+)/", cached)
                if m:
                    return cached
            except Exception:
                pass

    # `flutter run`'s stdout log has a host-local URI on both platforms (Android:
    # the DDS endpoint, already forwarded by flutter; desktop: native). Prefer
    # it. Point DRIVE_RUN_LOG at the right log when a Linux session owns the
    # default path, so Android doesn't read a stale Linux URI.
    uri = _scan_flutter_run_log_for_vm_uri()
    if uri:
        ws = uri.replace("http://", "ws://").rstrip("/") + "/ws"
        WS_CACHE.write_text(ws)
        return ws

    if IS_DESKTOP:
        raise RuntimeError(
            f"could not find Dart VM service URI in {FLUTTER_RUN_LOG}. "
            f"Is `flutter run -d {TARGET}` running in debug mode?")

    uri = _scan_logcat_for_vm_uri(serial)
    if not uri:
        raise RuntimeError(
            "could not find Dart VM service URI in /tmp/flutter_run.log or "
            "logcat. Is a debug build of the app running on the emulator?")
    remote_port, token = _parse_vm_uri(uri)
    local_port = _forward_port(remote_port, serial=serial)
    ws = _ws_uri(local_port, token)
    WS_CACHE.write_text(ws)
    return ws


# ---------------------------------------------------------------------------
# JSON-RPC client over WebSocket
# ---------------------------------------------------------------------------

_REQ_ID = 0


async def _call_async(ws_uri: str, method: str, params: dict[str, Any]) -> Any:
    global _REQ_ID
    _REQ_ID += 1
    req_id = _REQ_ID
    payload = {
        "jsonrpc": "2.0",
        "id": req_id,
        "method": method,
        "params": params,
    }
    # Reasonable timeout per RPC; long-running operations (refresh library)
    # should still complete under this budget for an idle emulator.
    async with websockets.connect(ws_uri, max_size=8 * 1024 * 1024) as ws:
        await ws.send(json.dumps(payload))
        while True:
            raw = await asyncio.wait_for(ws.recv(), timeout=30)
            msg = json.loads(raw)
            if msg.get("id") == req_id:
                if "error" in msg:
                    raise RuntimeError(json.dumps(msg["error"]))
                return msg.get("result")


def call(ws_uri: str, method: str, params: dict[str, Any] | None = None) -> Any:
    """Synchronous wrapper around an async JSON-RPC call."""
    return asyncio.run(_call_async(ws_uri, method, params or {}))


def _ext(ws_uri: str, ext_method: str, params: dict[str, Any] | None = None) -> Any:
    """Call a service extension. The VM service expects extension methods to be
    dispatched as their own method names; pass through the isolate that owns
    them by including the targeted isolate in params when needed."""
    # Find an isolate to scope the call to.
    vm = call(ws_uri, "getVM", {})
    isolates = vm.get("isolates", [])
    if not isolates:
        raise RuntimeError("VM has no isolates yet — is the app fully started?")
    isolate_id = isolates[0].get("id")
    full_params = dict(params or {})
    full_params.setdefault("isolateId", isolate_id)
    return call(ws_uri, ext_method, full_params)


def _ext_resilient(ext_method: str, params: dict[str, Any] | None = None,
                   serial: str = DEFAULT_SERIAL,
                   _retried: bool = False) -> Any:
    """Wrap _ext with automatic rediscovery of the WS URI on transport errors."""
    try:
        ws = _resolve_ws(serial=serial)
        return _ext(ws, ext_method, params)
    except Exception as e:
        if _retried:
            raise
        # Refresh and retry once. Most commonly the cached URI is from a prior
        # cold launch, or the emulator restarted.
        if WS_CACHE.exists():
            WS_CACHE.unlink(missing_ok=True)
        _resolve_ws(serial=serial, force=True)
        return _ext_resilient(ext_method, params, serial=serial, _retried=True)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_inspect(args) -> int:
    out = {
        "router": _ext_resilient("ext.nothingness.getRouterState"),
        "library": _ext_resilient("ext.nothingness.getLibraryState"),
        "playback": _ext_resilient("ext.nothingness.getPlaybackState"),
        "overflows": _ext_resilient("ext.nothingness.getOverflowReports"),
    }
    print(json.dumps(out, indent=2))
    return 0


def cmd_screen(args) -> int:
    name = args.name
    if name == "void":
        name = "void"  # AgentService accepts both `void` and `void_`
    res = _ext_resilient("ext.nothingness.setSetting",
                         {"name": "screen", "value": name})
    print(json.dumps(res, indent=2))
    return 0


def cmd_variant(args) -> int:
    res = _ext_resilient("ext.nothingness.setSetting",
                         {"name": "themeVariant", "value": args.name})
    print(json.dumps(res, indent=2))
    return 0


def cmd_mode(args) -> int:
    res = _ext_resilient("ext.nothingness.setSetting",
                         {"name": "operatingMode", "value": args.name})
    print(json.dumps(res, indent=2))
    return 0


_PHONE_PRESETS = {
    "phone": "390x844",       # iPhone 14-ish portrait
    "small": "360x800",       # common small Android portrait
    "tall": "412x915",        # Pixel-ish portrait
    "tiny": "280x653",        # adversarial narrow portrait
    "off": "off",
}


def cmd_emulate(args) -> int:
    """drive.py emulate <phone|small|tall|tiny|off|WxH>  (B-042 phone frame)."""
    spec = _PHONE_PRESETS.get(args.spec, args.spec)
    res = _ext_resilient("ext.nothingness.setSetting",
                         {"name": "phoneFrame", "value": spec})
    print(json.dumps(res, indent=2))
    return 0


def cmd_window(args) -> int:
    """drive.py window <w> <h>  (B-042) — set an exact phone-frame size."""
    res = _ext_resilient("ext.nothingness.setSetting",
                         {"name": "phoneFrame", "value": f"{args.width}x{args.height}"})
    print(json.dumps(res, indent=2))
    return 0


def cmd_nav(args) -> int:
    res = _ext_resilient("ext.nothingness.navigateVoid", {"path": args.path})
    print(json.dumps(res, indent=2))
    return 0


def cmd_up(args) -> int:
    res = _ext_resilient("ext.nothingness.navigateVoidUp")
    print(json.dumps(res, indent=2))
    return 0


def cmd_settings(args) -> int:
    if args.action == "open":
        res = _ext_resilient("ext.nothingness.openSettingsSheet")
    elif args.action == "close":
        res = _ext_resilient("ext.nothingness.closeSettingsSheet")
    else:
        print(f"unknown action {args.action}", file=sys.stderr)
        return 2
    print(json.dumps(res, indent=2))
    return 0


def cmd_play(args) -> int:
    res = _ext_resilient("ext.nothingness.playTrackByPath", {"path": args.path})
    print(json.dumps(res, indent=2))
    return 0


def cmd_pause(args) -> int:
    res = _ext_resilient("ext.nothingness.pause")
    print(json.dumps(res, indent=2))
    return 0


def cmd_resume(args) -> int:
    res = _ext_resilient("ext.nothingness.play")
    print(json.dumps(res, indent=2))
    return 0


def cmd_next(args) -> int:
    res = _ext_resilient("ext.nothingness.next")
    print(json.dumps(res, indent=2))
    return 0


def cmd_prev(args) -> int:
    res = _ext_resilient("ext.nothingness.prev")
    print(json.dumps(res, indent=2))
    return 0


def cmd_pref(args) -> int:
    # Format: key=value:type
    spec = args.spec
    if "=" not in spec:
        print("pref expects key=value[:type]", file=sys.stderr)
        return 2
    key, rest = spec.split("=", 1)
    if ":" in rest:
        value, type_ = rest.rsplit(":", 1)
    else:
        value, type_ = rest, "string"
    res = _ext_resilient("ext.nothingness.setPreference",
                         {"key": key, "value": value, "type": type_})
    print(json.dumps(res, indent=2))
    return 0


def cmd_clearpref(args) -> int:
    res = _ext_resilient("ext.nothingness.clearPreference", {"key": args.key})
    print(json.dumps(res, indent=2))
    return 0


def cmd_permit(args) -> int:
    res = _ext_resilient("ext.nothingness.requestLibraryPermission")
    print(json.dumps(res, indent=2))
    return 0


def cmd_shoot(args) -> int:
    out = SHOTS_DIR / f"{args.name}.png"
    if IS_DESKTOP:
        # Desktop has no adb screencap; ask the app to rasterize its current
        # frame via ext.nothingness.screenshot. Returns base64 PNG bytes.
        params: dict[str, Any] = {}
        if getattr(args, "pixel_ratio", None) is not None:
            params["pixelRatio"] = str(args.pixel_ratio)
        res = _ext_resilient("ext.nothingness.screenshot", params)
        b64 = (res or {}).get("png_base64") if isinstance(res, dict) else None
        if not b64:
            print(json.dumps({"shot": False, "error": "no png_base64 in response",
                              "response": res}, indent=2))
            return 1
        out.write_bytes(base64.b64decode(b64))
        info = {"path": str(out),
                "width": res.get("width"), "height": res.get("height")}
        print(json.dumps(info, indent=2))
        return 0
    # Android: prefer fast binary path via `adb exec-out screencap -p`. Falls
    # back to a device-side write + pull on platforms where exec-out is finicky.
    try:
        proc = subprocess.run(
            ["adb", "-s", DEFAULT_SERIAL, "exec-out", "screencap", "-p"],
            check=True,
            capture_output=True,
            timeout=20,
        )
        out.write_bytes(proc.stdout)
    except Exception:
        device_tmp = f"/sdcard/{args.name}.png"
        adb("shell", "screencap", "-p", device_tmp)
        adb("pull", device_tmp, str(out))
        adb("shell", "rm", device_tmp)
    print(json.dumps({"path": str(out)}, indent=2))
    return 0


def cmd_tree(args) -> int:
    params = {}
    if args.depth is not None:
        params["depth"] = str(args.depth)
    res = _ext_resilient("ext.nothingness.getWidgetTree", params)
    if isinstance(res, dict) and "tree" in res:
        # Avoid double-escaped output; print the tree raw.
        print(res["tree"])
    else:
        print(json.dumps(res, indent=2))
    return 0


def cmd_tap(args) -> int:
    res = _ext_resilient("ext.nothingness.tapByKey", {"key": args.key})
    print(json.dumps(res, indent=2))
    return 0


def cmd_logcat(args) -> int:
    n = args.lines or 200
    if IS_DESKTOP:
        # No logcat on desktop; tail the `flutter run` log instead.
        if not FLUTTER_RUN_LOG.exists():
            print(f"{FLUTTER_RUN_LOG} does not exist; is `flutter run -d {TARGET}` "
                  "redirecting stdout there?", file=sys.stderr)
            return 1
        try:
            lines = FLUTTER_RUN_LOG.read_text(errors="ignore").splitlines()
        except OSError as e:
            print(f"failed to read {FLUTTER_RUN_LOG}: {e}", file=sys.stderr)
            return 1
        sys.stdout.write("\n".join(lines[-n:]) + "\n")
        return 0
    proc = adb("logcat", "-d", "-v", "brief", "-t", str(n), check=False)
    sys.stdout.write(proc.stdout)
    return 0


def cmd_overflows(args) -> int:
    params = {}
    if args.clear:
        params["clear"] = "true"
    res = _ext_resilient("ext.nothingness.getOverflowReports", params)
    print(json.dumps(res, indent=2))
    return 0


def _flutter_fifo_write(command: str) -> bool:
    """Send a key command (e.g. 'r' / 'R') to flutter run's stdin via fifo.

    Returns True if the fifo exists and the write succeeded."""
    fifo = Path("/tmp/flutter_input")
    if not fifo.exists():
        return False
    try:
        # The fifo must already have a long-lived reader (flutter run) and a
        # long-lived writer holding it open (the sleep-infinity helper).
        with open(fifo, "w") as f:
            f.write(command + "\n")
            f.flush()
        return True
    except Exception:
        return False


def cmd_reload(args) -> int:
    """Hot reload via flutter run's stdin (sends 'r'). Falls back to
    error if no flutter run is attached. Forces drive.py to invalidate the
    cached WS URI in case sources structurally changed."""
    ok = _flutter_fifo_write("r")
    if not ok:
        print(json.dumps({
            "reloaded": False,
            "error": "no /tmp/flutter_input fifo; is `flutter run` running?",
        }, indent=2))
        return 2
    # Reload doesn't change the VM URI but does invalidate kernel — give the
    # tool a moment to push & apply.
    time.sleep(args.delay or 1.5)
    print(json.dumps({"reloaded": True, "kind": "hot-reload"}, indent=2))
    return 0


def cmd_restart(args) -> int:
    """Hot restart via flutter run's stdin (sends 'R')."""
    ok = _flutter_fifo_write("R")
    if not ok:
        print(json.dumps({
            "restarted": False,
            "error": "no /tmp/flutter_input fifo; is `flutter run` running?",
        }, indent=2))
        return 2
    time.sleep(args.delay or 3.0)
    # State is wiped on restart; AgentService re-registers; clear cache so the
    # next call rediscovers (in case the URI changed).
    WS_CACHE.unlink(missing_ok=True)
    print(json.dumps({"restarted": True, "kind": "hot-restart"}, indent=2))
    return 0


def _flutter_run_alive(max_age_s: float = 300.0) -> bool:
    """Best-effort detection of a live `flutter run` session.

    Returns True when:
      1. `/tmp/flutter_run.log` exists and was modified within the last
         ``max_age_s`` seconds (default 5 min — flutter run keeps tickling
         the log via heartbeat / progress lines), AND
      2. The cached VM service URI (``.vm_ws.txt``) still answers a quick
         ``ext.nothingness.getRouterState`` probe.

    Both signals are required: the log alone can linger from a crashed
    session, and the WS cache alone could point at a stand-alone debug
    APK with no flutter run attached.
    """
    try:
        if not FLUTTER_RUN_LOG.exists():
            return False
        if (time.time() - FLUTTER_RUN_LOG.stat().st_mtime) > max_age_s:
            return False
    except OSError:
        return False
    if not WS_CACHE.exists():
        return False
    try:
        ws = WS_CACHE.read_text().strip()
        if not ws:
            return False
        # Short-circuit probe: if the extension responds, the session is up.
        _ext(ws, "ext.nothingness.getRouterState")
        return True
    except Exception:
        return False


def cmd_reset(args) -> int:
    """Force-stop, clear app data, cold launch, wait for VM service."""
    if IS_DESKTOP:
        print(json.dumps({
            "reset": False,
            "reason": (
                f"`drive.py reset` is Android-only (uses adb force-stop + "
                f"pm clear). On {TARGET} desktop, stop and restart "
                f"`flutter run -d {TARGET}` manually to wipe state, or use "
                f"`drive.py restart` for a hot restart."
            ),
        }, indent=2))
        return 1
    if _flutter_run_alive() and not getattr(args, "force", False):
        print(json.dumps({
            "reset": False,
            "reason": (
                "live `flutter run` session detected "
                "(/tmp/flutter_run.log fresh + VM service responsive). "
                "`drive.py reset` would force-stop the app and crash the "
                "session, forcing a 60-90 s rebuild. Use `drive.py restart` "
                "for a hot restart, or pass `--force` to override."
            ),
        }, indent=2))
        return 1
    adb("shell", "am", "force-stop", APP_ID, check=False)
    adb("shell", "pm", "clear", APP_ID)
    WS_CACHE.unlink(missing_ok=True)
    adb("shell", "am", "start", "-W",
        "-n", f"{APP_ID}/{LAUNCH_ACTIVITY}", check=False)
    # Wait for VM service to appear in logcat (debug build).
    deadline = time.time() + 60
    uri = None
    while time.time() < deadline:
        uri = _scan_logcat_for_vm_uri(DEFAULT_SERIAL, max_lines=2000)
        if uri:
            break
        time.sleep(1.5)
    if not uri:
        print(json.dumps({"reset": True, "vm": None,
                          "note": "VM service not seen; release build?"}, indent=2))
        return 0
    # Re-establish forward + cache.
    remote_port, token = _parse_vm_uri(uri)
    _forward_port(remote_port)
    WS_CACHE.write_text(_ws_uri(LOCAL_FORWARD_PORT, token))
    print(json.dumps({"reset": True, "vm": WS_CACHE.read_text()}, indent=2))
    return 0


def cmd_replay(args) -> int:
    script = Path(args.script)
    if not script.exists():
        print(f"no such file: {script}", file=sys.stderr)
        return 2
    rc = 0
    for raw in script.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        argv = shlex.split(line)
        if argv and argv[0] == "drive.py":
            argv = argv[1:]
        print(f"\n$ drive.py {' '.join(argv)}")
        rc = main(argv) or 0
        if rc != 0:
            print(f"replay aborting on exit {rc}", file=sys.stderr)
            break
    return rc


def cmd_call(args) -> int:
    """Raw call: drive.py call ext.nothingness.<method> [k=v ...]"""
    params: dict[str, Any] = {}
    for kv in args.kvs or []:
        if "=" not in kv:
            print(f"bad param {kv!r}", file=sys.stderr)
            return 2
        k, v = kv.split("=", 1)
        params[k] = v
    res = _ext_resilient(args.method, params)
    print(json.dumps(res, indent=2))
    return 0


# ---------------------------------------------------------------------------
# Argparse
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="drive.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("inspect").set_defaults(func=cmd_inspect)

    sp = sub.add_parser("screen")
    sp.add_argument("name", choices=["spectrum", "polo", "dot", "void"])
    sp.set_defaults(func=cmd_screen)

    sp = sub.add_parser("variant")
    sp.add_argument("name", choices=["dark", "light", "system"])
    sp.set_defaults(func=cmd_variant)

    sp = sub.add_parser("mode")
    sp.add_argument("name", choices=["own", "background"])
    sp.set_defaults(func=cmd_mode)

    sp = sub.add_parser("nav")
    sp.add_argument("path")
    sp.set_defaults(func=cmd_nav)

    sub.add_parser("up").set_defaults(func=cmd_up)

    sp = sub.add_parser("settings")
    sp.add_argument("action", choices=["open", "close"])
    sp.set_defaults(func=cmd_settings)

    sp = sub.add_parser("play")
    sp.add_argument("path")
    sp.set_defaults(func=cmd_play)

    sub.add_parser("pause").set_defaults(func=cmd_pause)
    sub.add_parser("resume").set_defaults(func=cmd_resume)
    sub.add_parser("next").set_defaults(func=cmd_next)
    sub.add_parser("prev").set_defaults(func=cmd_prev)

    sp = sub.add_parser("pref")
    sp.add_argument("spec", help="key=value[:type] where type is bool/int/double/string/stringlist")
    sp.set_defaults(func=cmd_pref)

    sp = sub.add_parser("clearpref")
    sp.add_argument("key", help="preference key or '*' to wipe all")
    sp.set_defaults(func=cmd_clearpref)

    sub.add_parser("permit").set_defaults(func=cmd_permit)

    sp = sub.add_parser("shoot")
    sp.add_argument("name")
    sp.add_argument(
        "--pixel-ratio", type=float, default=None,
        help="raster scale for the screenshot (default 1.0; "
        "desktop / VM-service path only)")
    sp.set_defaults(func=cmd_shoot)

    sp = sub.add_parser("tree")
    sp.add_argument("depth", type=int, nargs="?")
    sp.set_defaults(func=cmd_tree)

    sp = sub.add_parser("tap")
    sp.add_argument("key")
    sp.set_defaults(func=cmd_tap)

    sp = sub.add_parser("logcat")
    sp.add_argument("lines", type=int, nargs="?")
    sp.set_defaults(func=cmd_logcat)

    sp = sub.add_parser("overflows")
    sp.add_argument("--clear", action="store_true")
    sp.set_defaults(func=cmd_overflows)

    sp = sub.add_parser(
        "reset",
        help="force-stop + clear data + cold launch (refuses when a live "
        "`flutter run` is attached; pass --force to override)")
    sp.add_argument(
        "--force", action="store_true",
        help="reset even when a live `flutter run` session is detected "
        "(this will crash that session and trigger a 60-90 s rebuild)")
    sp.set_defaults(func=cmd_reset)

    sp = sub.add_parser("reload", help="hot reload via `flutter run` fifo")
    sp.add_argument("--delay", type=float, help="seconds to wait after sending r")
    sp.set_defaults(func=cmd_reload)

    sp = sub.add_parser("restart", help="hot restart via `flutter run` fifo")
    sp.add_argument("--delay", type=float, help="seconds to wait after sending R")
    sp.set_defaults(func=cmd_restart)

    sp = sub.add_parser("replay")
    sp.add_argument("script")
    sp.set_defaults(func=cmd_replay)

    sp = sub.add_parser("call")
    sp.add_argument("method")
    sp.add_argument("kvs", nargs="*")
    sp.set_defaults(func=cmd_call)

    # B-042: debug phone-frame on the desktop build.
    sp = sub.add_parser(
        "emulate",
        help="phone-frame the desktop app: phone|small|tall|tiny|off|WxH",
    )
    sp.add_argument("spec", help="preset (phone|small|tall|tiny|off) or WxH e.g. 390x844")
    sp.set_defaults(func=cmd_emulate)

    sp = sub.add_parser("window", help="set exact phone-frame size (B-042)")
    sp.add_argument("width", type=int)
    sp.add_argument("height", type=int)
    sp.set_defaults(func=cmd_window)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args) or 0
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
