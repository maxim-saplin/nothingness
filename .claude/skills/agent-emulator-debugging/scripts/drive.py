#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["websockets>=12.0"]
# ///
"""drive.py — CLI driver for the Nothingness app's VM service surface.

Wraps `ext.nothingness.*` extensions exposed by `dev/agent_service.dart`
so a human or agent can puppet the live app without writing one-off scripts.

Targets:
  - **android** (default) — drives an emulator/device through `adb`.
  - **linux** / **macos** — drives a Flutter desktop build of the app. ADB
    is bypassed; the VM service URI is read from `/tmp/flutter_run.log` and
    `shoot` rasterizes via `ext.nothingness.screenshot` (no `adb screencap`).

The target is picked from `DRIVE_TARGET`; if unset drive.py sniffs
`/tmp/flutter_run.log` ("...on Linux in debug mode"), and only then falls back
to `android`. Which targets are actually reachable is NOT assumed — run
`drive.py preflight` to detect the host (WSL?), flutter devices, adb, and any
live `flutter run`, and to get a recommended next command.

Subcommands print structured JSON on stdout and exit 0 on success, non-zero on
RPC error.

Usage (a few examples):
  drive.py preflight                     # detect environment + recommend next cmd
  drive.py contract                      # list registered ext.nothingness.* + count
  drive.py inspect                       # router + library + playback + overflow
  drive.py screen void                   # set the active home screen (spectrum|polo|dot|void|cassette)
  drive.py cassettevariant 3             # select cassette variant 1..7 (or v1..v7)
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


# Some raw VM RPCs (notably getCpuSamples / getVMTimeline) return payloads far
# larger than the 8 MiB used for extension traffic — bump the frame ceiling.
_RAW_MAX_SIZE = 64 * 1024 * 1024


async def _raw_call_async(ws_uri: str, method: str, params: dict[str, Any]) -> Any:
    """Like _call_async but tolerates very large response frames."""
    global _REQ_ID
    _REQ_ID += 1
    req_id = _REQ_ID
    payload = {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}
    async with websockets.connect(ws_uri, max_size=_RAW_MAX_SIZE) as ws:
        await ws.send(json.dumps(payload))
        while True:
            raw = await asyncio.wait_for(ws.recv(), timeout=30)
            msg = json.loads(raw)
            if msg.get("id") == req_id:
                if "error" in msg:
                    raise RuntimeError(json.dumps(msg["error"]))
                return msg.get("result")


def _raw_resilient(method: str, params: dict[str, Any] | None = None,
                   scoped: bool = False, serial: str = DEFAULT_SERIAL,
                   _retried: bool = False) -> Any:
    """Call a RAW VM-protocol RPC (not an ext.nothingness.* extension) with the
    same delete-cache-and-retry-once-on-error resilience as _ext_resilient.

    When ``scoped`` is True the active isolateId is resolved (getVM ->
    isolates[0].id) and injected into params, matching ``_ext``; otherwise the
    method is dispatched VM-globally as-is.
    """
    try:
        ws = _resolve_ws(serial=serial)
        full = dict(params or {})
        if scoped:
            vm = call(ws, "getVM", {})
            isolates = vm.get("isolates", [])
            if not isolates:
                raise RuntimeError("VM has no isolates yet — is the app started?")
            full.setdefault("isolateId", isolates[0].get("id"))
        return asyncio.run(_raw_call_async(ws, method, full))
    except Exception:
        if _retried:
            raise
        if WS_CACHE.exists():
            WS_CACHE.unlink(missing_ok=True)
        _resolve_ws(serial=serial, force=True)
        return _raw_resilient(method, params, scoped=scoped, serial=serial,
                              _retried=True)


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


def cmd_cassette_variant(args) -> int:
    """Select cassette variant 1..7.  drive.py cassettevariant 3"""
    res = _ext_resilient("ext.nothingness.setSetting",
                         {"name": "cassetteVariant", "value": args.n})
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
# Contract: discover the registered extension surface from the LIVE isolate
# ---------------------------------------------------------------------------

def _registered_extensions(ws: str) -> list[str]:
    """Return the `ext.nothingness.*` extension names the live isolate actually
    registered, read from `getIsolate.extensionRPCs` — never hardcoded.

    Adapts if a future VM exposes the list under a different field by scanning
    the isolate dict for any list of `ext.nothingness.*` strings."""
    vm = call(ws, "getVM", {})
    isolates = vm.get("isolates", [])
    if not isolates:
        raise RuntimeError("VM has no isolates yet — is the app fully started?")
    # Prefer the 'main' isolate; fall back to the first.
    main = next((i for i in isolates if i.get("name") == "main"), isolates[0])
    iso = call(ws, "getIsolate", {"isolateId": main.get("id")})
    rpcs = iso.get("extensionRPCs")
    if not isinstance(rpcs, list):
        # Adapt: hunt for any list-of-strings field that looks like ext names.
        rpcs = []
        for v in iso.values():
            if isinstance(v, list) and any(
                    isinstance(x, str) and x.startswith("ext.") for x in v):
                rpcs = v
                break
    return sorted(r for r in rpcs if isinstance(r, str)
                  and r.startswith("ext.nothingness."))


def cmd_contract(args) -> int:
    """drive.py contract — list the ext.nothingness.* extensions the running
    build actually registered, plus their count. Use this instead of citing a
    hardcoded number anywhere."""
    ws = _resolve_ws()
    names = _registered_extensions(ws)
    out = {"count": len(names), "extensions": names}
    print(json.dumps(out, indent=2))
    return 0


# ---------------------------------------------------------------------------
# Runtime-inspection subcommands (probe / frames / timeline / profile / breakpoint)
# ---------------------------------------------------------------------------

def cmd_probe(args) -> int:
    """drive.py probe <key> — dump the text + style of a keyed Text widget."""
    res = _ext_resilient("ext.nothingness.probeText", {"key": args.key})
    print(json.dumps(res, indent=2))
    return 0


def cmd_frames(args) -> int:
    """drive.py frames [--clear] — frame-timing / jank summary."""
    params = {"clear": "true"} if args.clear else {}
    res = _ext_resilient("ext.nothingness.getFrameTimings", params)
    print(json.dumps(res, indent=2))
    return 0


def cmd_timeline(args) -> int:
    """drive.py timeline [--clear] — VM timeline summary (Dart/Embedder/GC).

    --clear arms the recorded streams and wipes the buffer; without it, fetches
    the buffer and prints a per-name summary plus any agent.* / transport.*
    marked spans (the skip instrumentation)."""
    if args.clear:
        _raw_resilient("setVMTimelineFlags",
                       {"recordedStreams": ["Dart", "Embedder", "GC"]})
        _raw_resilient("clearVMTimeline")
        print(json.dumps({"cleared": True}, indent=2))
        return 0

    res = _raw_resilient("getVMTimeline")
    events = res.get("traceEvents", [])
    summary: dict[str, dict[str, int]] = {}
    marked: list[dict[str, Any]] = []
    for e in events:
        name = e.get("name", "")
        dur = e.get("dur")
        if isinstance(dur, (int, float)):
            s = summary.setdefault(
                name, {"count": 0, "total_dur_us": 0, "max_dur_us": 0})
            s["count"] += 1
            s["total_dur_us"] += int(dur)
            s["max_dur_us"] = max(s["max_dur_us"], int(dur))
        if name.startswith("agent.") or name.startswith("transport."):
            if len(marked) < 50:
                marked.append({
                    "name": name,
                    "ts": e.get("ts"),
                    "dur": dur,
                    "args": e.get("args"),
                })
    out = {"summary": summary, "marked_spans": marked,
           "total_events": len(events)}
    print(json.dumps(out, indent=2))
    return 0


def _profile_capture(iso_anchor: int, args) -> Any:
    """One getCpuSamples attempt over a forward window from ``iso_anchor``."""
    extent = int(args.seconds * 1_000_000) if args.seconds else 5_000_000
    return _raw_resilient(
        "getCpuSamples",
        {"timeOriginMicros": iso_anchor, "timeExtentMicros": extent},
        scoped=True)


def cmd_profile(args) -> int:
    """drive.py profile [--seconds N] — CPU self-time profile (does NOT pause).

    Samples the recent CPU buffer; with --seconds the driver sleeps that long
    first so the window captures fresh activity. Fire `drive.py next`/`play`
    from another shell during the window to profile skips."""
    # getVMTimestamp is unavailable on this VM; use the timeline's own clock
    # (timeOriginMicros + timeExtentMicros ≈ "now") as the monotonic anchor.
    tl = _raw_resilient("getVMTimeline")
    t0 = int(tl.get("timeOriginMicros", 0)) + int(tl.get("timeExtentMicros", 0))

    if args.seconds:
        time.sleep(args.seconds)

    extent = int(args.seconds * 1_000_000) if args.seconds else 5_000_000
    res = _profile_capture(t0, args)
    note = None
    if not res.get("sampleCount"):
        # Origin may sit ahead of the buffered samples; fall back to a wide
        # window ending at the anchor.
        back = int((args.seconds or 5) * 1_000_000)
        res = _raw_resilient(
            "getCpuSamples",
            {"timeOriginMicros": max(0, t0 - back), "timeExtentMicros": back},
            scoped=True)
        note = "used fallback window (forward window had no samples)"

    samples = res.get("samples", [])
    functions = res.get("functions", [])

    def fn_name(i: int) -> str:
        try:
            f = functions[i].get("function", {}) or {}
            nm = f.get("name") or "<anonymous>"
            owner = f.get("owner")
            if isinstance(owner, dict) and owner.get("name"):
                return f"{owner['name']}.{nm}"
            return nm
        except (IndexError, AttributeError, TypeError):
            return f"<fn#{i}>"

    from collections import Counter
    leaves: Counter = Counter()
    for s in samples:
        stack = s.get("stack") or []
        if stack:
            leaves[stack[0]] += 1  # leaf-first ordering (verified live)

    total = sum(leaves.values()) or 1
    top = [
        {"function": fn_name(idx), "self_samples": cnt,
         "pct": round(100.0 * cnt / total, 2)}
        for idx, cnt in leaves.most_common(20)
    ]
    out = {"sampleCount": res.get("sampleCount", 0),
           "window_us": extent, "top": top}
    if not samples:
        out["note"] = note or "CPU sample buffer was empty for this window"
    elif note:
        out["note"] = note
    print(json.dumps(out, indent=2))
    return 0


def _render_instance(ref: Any) -> Any:
    """Best-effort render of an evaluateInFrame result (InstanceRef/ErrorRef)."""
    if not isinstance(ref, dict):
        return ref
    kind = ref.get("type") or ref.get("kind")
    if "valueAsString" in ref:
        return ref["valueAsString"]
    if ref.get("type") == "@Error" or ref.get("kind") == "Error":
        return {"error": ref.get("message") or ref.get("kind")}
    cls = ref.get("class") or {}
    return {"class": cls.get("name") if isinstance(cls, dict) else None,
            "id": ref.get("id"), "kind": kind}


async def _breakpoint_session(args) -> dict[str, Any]:
    """Persistent debug session: set a breakpoint, fire a trigger on a SEPARATE
    socket, wait for the pause, read stack + watches, then ALWAYS resume."""
    # Resolve the WS URI OUTSIDE any nested asyncio.run: we are already inside a
    # running loop here, so use _resolve_ws (sync, no loop) but never call() —
    # do getVM via the persistent socket's own _rpc instead.
    ws_uri = _resolve_ws()

    async def _rpc(ws, method, params):
        global _REQ_ID
        _REQ_ID += 1
        rid = _REQ_ID
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": rid,
                                  "method": method, "params": params}))
        while True:
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=args.timeout))
            if msg.get("id") == rid:
                if "error" in msg:
                    raise RuntimeError(json.dumps(msg["error"]))
                return msg.get("result")
            # streamNotify events arrive here too; ignore until we have the id.

    out: dict[str, Any] = {"hit": False, "stack": [], "watch": {}, "note": ""}
    bp_id = None
    iso = None
    async with websockets.connect(ws_uri, max_size=_RAW_MAX_SIZE) as ws:
        try:
            vm = await _rpc(ws, "getVM", {})
            iso = vm["isolates"][0]["id"]
            await _rpc(ws, "streamListen", {"streamId": "Debug"})
            bp = await _rpc(ws, "addBreakpointWithScriptUri",
                            {"isolateId": iso, "scriptUri": args.uri,
                             "line": args.line})
            bp_id = bp.get("id") if isinstance(bp, dict) else None

            # Fire the trigger FIRE-AND-FORGET on a separate connection: the
            # isolate pauses mid-execution so this RPC never returns.
            if args.trigger != "none":
                ext = f"ext.nothingness.{args.trigger}"

                async def _fire():
                    try:
                        async with websockets.connect(ws_uri) as t:
                            global _REQ_ID
                            _REQ_ID += 1
                            await t.send(json.dumps({
                                "jsonrpc": "2.0", "id": _REQ_ID, "method": ext,
                                "params": {"isolateId": iso}}))
                            await asyncio.wait_for(t.recv(), timeout=args.timeout)
                    except Exception:
                        pass  # expected: pause means no reply

                trigger_task = asyncio.ensure_future(_fire())
            else:
                trigger_task = None

            # Pump the session socket until a pause event (honoring --timeout).
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                remaining = max(0.1, deadline - time.monotonic())
                try:
                    msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=remaining))
                except asyncio.TimeoutError:
                    break
                if msg.get("method") != "streamNotify":
                    continue
                ev = msg.get("params", {}).get("event", {})
                if ev.get("kind") in ("PauseBreakpoint", "PauseInterrupted"):
                    out["hit"] = True
                    break

            if out["hit"]:
                stack = await _rpc(ws, "getStack", {"isolateId": iso})
                frames = stack.get("frames", [])[:8]
                rendered = []
                for f in frames:
                    fn = f.get("function") or {}
                    loc = f.get("location") or {}
                    script = loc.get("script") or {}
                    rendered.append({
                        "function": fn.get("name"),
                        "scriptUri": script.get("uri"),
                        "tokenPos": loc.get("tokenPos"),
                        "line": loc.get("line"),
                    })
                out["stack"] = rendered

                for expr in [e for e in args.watch.split(",") if e.strip()]:
                    expr = expr.strip()
                    try:
                        r = await _rpc(ws, "evaluateInFrame",
                                       {"isolateId": iso, "frameIndex": 0,
                                        "expression": expr})
                        out["watch"][expr] = _render_instance(r)
                    except Exception as ex:
                        out["watch"][expr] = {"error": str(ex)}
                out["note"] = "breakpoint hit; app resumed in finally"
            else:
                out["note"] = ("no pause within --timeout; app not paused "
                               "(breakpoint removed)")

            if trigger_task:
                trigger_task.cancel()
        except Exception as ex:
            out["note"] = f"error: {ex} (app resumed in finally)"
        finally:
            # NEVER leave the isolate paused. Remove the breakpoint, resume,
            # tolerate errors (isolate may already be running).
            if bp_id:
                try:
                    await _rpc(ws, "removeBreakpoint",
                               {"isolateId": iso, "breakpointId": bp_id})
                except Exception:
                    pass
            try:
                await _rpc(ws, "resume", {"isolateId": iso})
            except Exception:
                pass
    return out


def cmd_breakpoint(args) -> int:
    """drive.py breakpoint — set a TRUE VM breakpoint, fire a trigger, capture
    the stack + watch expressions, then ALWAYS resume.

    !!! DANGER !!! This PAUSES the UI isolate — while paused, EVERY
    ext.nothingness.* extension (and any other driver) is frozen. NEVER run this
    concurrently with another driver/agent. It always removes the breakpoint and
    resumes in a finally block, so the app is never left paused even on
    timeout/exception.
    """
    out = asyncio.run(_breakpoint_session(args))
    print(json.dumps(out, indent=2))
    return 0


# ---------------------------------------------------------------------------
# Preflight: detect the environment at runtime — nothing about which targets are
# reachable is written in stone; everything below is a live probe.
# ---------------------------------------------------------------------------

def _detect_host() -> dict[str, Any]:
    """Detect OS/platform and whether we're inside WSL — defensively."""
    info: dict[str, Any] = {"platform": sys.platform, "is_wsl": False,
                            "kernel": None}
    try:
        text = Path("/proc/version").read_text(errors="ignore")
        info["kernel"] = text.strip()[:200]
        if "microsoft" in text.lower() or "wsl" in text.lower():
            info["is_wsl"] = True
    except Exception:
        # Not Linux, or /proc unavailable — that's fine, just not WSL.
        pass
    try:
        info["uname"] = subprocess.run(
            ["uname", "-sr"], capture_output=True, text=True,
            timeout=5).stdout.strip() or None
    except Exception:
        info["uname"] = None
    return info


def _detect_flutter_devices() -> dict[str, Any]:
    """Run `flutter devices --machine` (JSON) if flutter is on PATH, else the
    plain text form. Tolerate flutter being slow/absent. Never raises."""
    out: dict[str, Any] = {"available": False, "devices": [], "error": None}
    from shutil import which
    if not which("flutter"):
        out["error"] = "flutter not on PATH"
        return out
    out["available"] = True
    try:
        proc = subprocess.run(
            ["flutter", "devices", "--machine"],
            capture_output=True, text=True, timeout=60)
        try:
            data = json.loads(proc.stdout)
        except Exception:
            data = None
        if isinstance(data, list):
            for d in data:
                if not isinstance(d, dict):
                    continue
                out["devices"].append({
                    "id": d.get("id"),
                    "name": d.get("name"),
                    "targetPlatform": d.get("targetPlatform"),
                    "emulator": d.get("emulator"),
                })
            return out
        # Fall through to text parse if --machine didn't yield JSON.
        proc = subprocess.run(
            ["flutter", "devices"], capture_output=True, text=True, timeout=60)
        out["raw"] = proc.stdout.strip()[:2000]
    except subprocess.TimeoutExpired:
        out["error"] = "flutter devices timed out (>60s)"
    except Exception as e:
        out["error"] = str(e)
    return out


def _flutter_targets(devices: list[dict[str, Any]]) -> dict[str, bool]:
    """Map raw flutter devices onto the drive.py target enum we care about."""
    targets = {"linux": False, "macos": False, "android": False, "chrome": False}
    for d in devices:
        tp = (d.get("targetPlatform") or "").lower()
        did = (d.get("id") or "").lower()
        if tp.startswith("linux") or did == "linux":
            targets["linux"] = True
        elif "darwin" in tp or did == "macos":
            targets["macos"] = True
        elif tp.startswith("android") or "android" in did or d.get("emulator"):
            targets["android"] = True
        elif "web" in tp or did == "chrome":
            targets["chrome"] = True
    return targets


def _detect_adb() -> dict[str, Any]:
    """Find an adb binary (PATH or $ANDROID_HOME/platform-tools/adb) and run
    `adb devices`. Never raises."""
    from shutil import which
    out: dict[str, Any] = {"adb_path": None, "devices": [], "error": None}
    adb_bin = which("adb")
    if not adb_bin:
        home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
        if home:
            cand = Path(home) / "platform-tools" / "adb"
            if cand.exists():
                adb_bin = str(cand)
    if not adb_bin:
        out["error"] = "no adb on PATH or $ANDROID_HOME/platform-tools"
        return out
    out["adb_path"] = adb_bin
    try:
        proc = subprocess.run(
            [adb_bin, "devices"], capture_output=True, text=True, timeout=15)
        for line in proc.stdout.splitlines()[1:]:
            line = line.strip()
            if not line or "\t" not in line:
                continue
            serial, state = line.split("\t", 1)
            out["devices"].append({"serial": serial.strip(),
                                   "state": state.strip()})
    except subprocess.TimeoutExpired:
        out["error"] = "adb devices timed out"
    except Exception as e:
        out["error"] = str(e)
    return out


def _detect_live_run() -> dict[str, Any]:
    """Is there a live `flutter run` with a responsive VM service? Reports the
    run-log freshness, the resolved ws URI, and the live isolate count. Never
    raises."""
    out: dict[str, Any] = {
        "run_log": str(FLUTTER_RUN_LOG),
        "log_present": False, "log_age_s": None, "log_fresh": False,
        "vm_uri": None, "ws": None, "vm_responds": False,
        "isolate_count": None, "extension_count": None, "error": None,
    }
    try:
        if FLUTTER_RUN_LOG.exists():
            out["log_present"] = True
            age = time.time() - FLUTTER_RUN_LOG.stat().st_mtime
            out["log_age_s"] = round(age, 1)
            out["log_fresh"] = age < 300.0
    except Exception as e:
        out["error"] = f"log stat: {e}"
    # Resolve the ws URI without mutating cache behaviour beyond what the normal
    # path does. Reuse the existing scanner + resolver.
    try:
        out["vm_uri"] = _scan_flutter_run_log_for_vm_uri()
    except Exception:
        pass
    try:
        ws = _resolve_ws()
        out["ws"] = ws
        vm = call(ws, "getVM", {})
        isolates = vm.get("isolates", [])
        out["isolate_count"] = len(isolates)
        out["vm_responds"] = len(isolates) > 0
        try:
            out["extension_count"] = len(_registered_extensions(ws))
        except Exception:
            pass
    except Exception as e:
        out["error"] = (out["error"] + "; " if out["error"] else "") + \
            f"vm: {e}"
    return out


def _recommend(host, fdevs, adb_info, live, ftargets) -> dict[str, Any]:
    """Turn the probes into a DRIVE_TARGET + a copy-pasteable next command. No
    verdict is hardcoded — it follows what's actually reachable."""
    drive_target = TARGET  # what drive.py would resolve to right now
    if live.get("vm_responds"):
        # A live VM is reachable — drive it directly with the resolved target.
        if IS_DESKTOP:
            return {
                "status": "ready",
                "drive_target": TARGET,
                "next": f"DRIVE_TARGET={TARGET} drive.py inspect",
                "why": f"live {TARGET} VM responds "
                       f"({live.get('isolate_count')} isolate(s))",
            }
        return {
            "status": "ready",
            "drive_target": TARGET,
            "next": "drive.py inspect",
            "why": f"live VM responds ({live.get('isolate_count')} isolate(s))",
        }

    # No live run. Recommend the cheapest reachable launch.
    if ftargets.get("linux"):
        return {
            "status": "needs-launch",
            "drive_target": "linux",
            "next": (
                "[ -p /tmp/flutter_input ] || mkfifo /tmp/flutter_input; "
                "nohup sleep infinity > /tmp/flutter_input & "
                "nohup flutter run -d linux --debug -t dev/main_debug.dart "
                "< /tmp/flutter_input > /tmp/flutter_run.log 2>&1 & "
                "export DRIVE_TARGET=linux"),
            "why": "linux desktop target present; no live run detected",
        }
    emu = [d for d in adb_info.get("devices", [])
           if d.get("state") == "device"]
    if emu or ftargets.get("android"):
        serial = emu[0]["serial"] if emu else "emulator-5554"
        return {
            "status": "needs-launch",
            "drive_target": "android",
            "next": (
                f"CI_EMULATOR_ABI=x86_64 flutter run -d {serial} --debug "
                "-t dev/main_debug.dart < /dev/null > /tmp/flutter_run.log 2>&1 &"
                "; export DRIVE_TARGET=android"),
            "why": (f"adb sees {serial}; x86_64 build required on an x86 "
                    "emulator (see B-045)"),
        }
    return {
        "status": "no-target",
        "drive_target": None,
        "next": ("no reachable target. Start a Linux desktop run "
                 "(`flutter run -d linux -t dev/main_debug.dart`) or boot an "
                 "Android emulator, then re-run `drive.py preflight`."),
        "why": "no live VM, no linux device, no adb device",
    }


def cmd_preflight(args) -> int:
    """drive.py preflight — detect the environment at runtime and recommend the
    next command. Each probe is wrapped so one failure still yields a full
    report; nothing about target availability is hardcoded."""
    report: dict[str, Any] = {}
    for key, fn in (
        ("host", _detect_host),
        ("flutter_devices", _detect_flutter_devices),
        ("adb", _detect_adb),
        ("live_run", _detect_live_run),
    ):
        try:
            report[key] = fn()
        except Exception as e:  # belt-and-suspenders; probes already guard
            report[key] = {"error": str(e)}

    ftargets = _flutter_targets(report["flutter_devices"].get("devices", []))
    report["flutter_targets"] = ftargets
    report["resolved_target"] = TARGET
    try:
        report["recommendation"] = _recommend(
            report["host"], report["flutter_devices"], report["adb"],
            report["live_run"], ftargets)
    except Exception as e:
        report["recommendation"] = {"status": "error", "error": str(e)}

    print(json.dumps(report, indent=2))

    # Human summary line(s) on stderr so JSON on stdout stays clean for agents.
    h = report["host"]
    rec = report["recommendation"]
    adb_n = len(report["adb"].get("devices", []))
    live = report["live_run"]
    summary = (
        f"[preflight] host={'WSL2' if h.get('is_wsl') else h.get('platform')} | "
        f"flutter targets={[k for k, v in ftargets.items() if v] or 'none'} | "
        f"adb devices={adb_n} | "
        f"live VM={'yes(' + str(live.get('isolate_count')) + ' iso)' if live.get('vm_responds') else 'no'} | "
        f"{rec.get('status')}: DRIVE_TARGET={rec.get('drive_target')}")
    print(summary, file=sys.stderr)
    print(f"[preflight] next: {rec.get('next')}", file=sys.stderr)
    return 0


# ---------------------------------------------------------------------------
# Argparse
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="drive.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser(
        "preflight",
        help="detect host/flutter/adb/live-run at runtime and recommend the "
        "next command (JSON on stdout, human summary on stderr)"
    ).set_defaults(func=cmd_preflight)

    sub.add_parser(
        "contract",
        help="list the ext.nothingness.* extensions the running build "
        "actually registered + their count (never hardcode the number)"
    ).set_defaults(func=cmd_contract)

    sub.add_parser("inspect").set_defaults(func=cmd_inspect)

    sp = sub.add_parser("screen")
    sp.add_argument("name", choices=["spectrum", "polo", "dot", "void", "cassette"])
    sp.set_defaults(func=cmd_screen)

    sp = sub.add_parser("variant")
    sp.add_argument("name", choices=["dark", "light", "system"])
    sp.set_defaults(func=cmd_variant)

    sp = sub.add_parser("cassettevariant",
                        help="select cassette variant 1..7 (requires cassette screen active)")
    sp.add_argument("n", choices=["1", "2", "3", "4", "5", "6", "7",
                                   "v1", "v2", "v3", "v4", "v5", "v6", "v7"])
    sp.set_defaults(func=cmd_cassette_variant)

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

    # Runtime inspection (DevTools-style).
    sp = sub.add_parser("probe", help="dump text+style of a keyed Text widget")
    sp.add_argument("key")
    sp.set_defaults(func=cmd_probe)

    sp = sub.add_parser("frames", help="frame-timing / jank summary")
    sp.add_argument("--clear", action="store_true",
                    help="clear the frame-timing buffer")
    sp.set_defaults(func=cmd_frames)

    sp = sub.add_parser(
        "timeline",
        help="VM timeline summary + agent.*/transport.* marked spans")
    sp.add_argument("--clear", action="store_true",
                    help="arm Dart/Embedder/GC streams and wipe the buffer")
    sp.set_defaults(func=cmd_timeline)

    sp = sub.add_parser(
        "profile",
        help="CPU self-time profile via getCpuSamples (does NOT pause the app)")
    sp.add_argument("--seconds", type=float, default=2.0,
                    help="driver sleeps this long to capture fresh activity "
                    "(default 2.0)")
    sp.set_defaults(func=cmd_profile)

    sp = sub.add_parser(
        "breakpoint",
        help="DANGER: set a TRUE VM breakpoint and capture stack+watch. PAUSES "
        "the UI isolate (freezing ALL ext.nothingness extensions) until it "
        "resumes in a finally; NEVER run concurrently with another driver.")
    sp.add_argument(
        "--uri",
        default="package:nothingness/services/playback_controller.dart",
        help="script URI to break in")
    sp.add_argument(
        "--line", type=int, default=692,
        help="line to break on (default 692: the `await _loadTrack(track)` "
        "call inside _playWithAutoAdvance)")
    sp.add_argument("--watch", default="",
                    help="comma-separated expressions to evaluate in frame 0")
    sp.add_argument("--trigger", choices=["next", "prev", "none"],
                    default="next", help="action that hits the breakpoint")
    sp.add_argument("--timeout", type=float, default=15,
                    help="seconds to wait for the pause (default 15)")
    sp.set_defaults(func=cmd_breakpoint)

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
