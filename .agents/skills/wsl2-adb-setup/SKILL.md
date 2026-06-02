---
name: wsl2-adb-setup
description: Use this skill when the user asks to set up ADB, configure Android device bridge, fix "adb devices shows nothing", troubleshoot ADB connectivity from WSL2, connect to a Windows-hosted Android emulator from Linux, or set up the WSL2/Windows ADB bridge. Activate any time ADB is not working from Claude's bash environment, or when onboarding a new dev machine for Android development with WSL2.
---

# WSL2 → Windows ADB Setup

This skill sets up secure, reliable ADB connectivity between a WSL2 Linux environment and an Android emulator (or device) running on the Windows host. It guides the user step by step, validates each stage, and leaves the system in a working state for both interactive use and autonomous (yolo-mode) agent operation.

## Why This Is Needed

WSL2 runs in a NAT-isolated Linux VM. The Android Emulator runs as a Windows process and connects to the Windows-side adb server on Windows `127.0.0.1:5037`. These are two separate network namespaces — Linux `adb` starts its own server that the emulator never connects to.

**Two options, one recommended:**

| | Option A: `adb.exe` shim | Option C: Mirrored networking |
|---|---|---|
| Works immediately | ✅ | Needs WSL restart |
| Pure Linux adb | ❌ | ✅ |
| Security | ⚠️ Allows arbitrary Windows code execution from WSL2 | ✅ Isolated — only ports are shared |
| Recommended | No | **Yes** |

**Always recommend Option C (mirrored networking).** Option A (calling `adb.exe` from WSL2) is a security hole — it lets any process in WSL2 run arbitrary Windows binaries with your Windows user's full privileges. In yolo/autonomous mode that blast radius is unacceptable.

---

## Step-by-Step Setup

### Step 1: Quick diagnostics

Run this first and report what is currently active:

```bash
which adb && adb version
adb devices
cat /mnt/c/Users/$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')/.wslconfig 2>/dev/null || echo "No .wslconfig"
cat /etc/wsl.conf 2>/dev/null || echo "No /etc/wsl.conf"
```

### Step 2: Configure both files in one pass

Keep all WSL networking and interop settings in one place (this step). Write both config files before restart.

Target files:
- Windows side: `C:\Users\<user>\.wslconfig` (from WSL: `/mnt/c/Users/<user>/.wslconfig`)
- Linux side: `/etc/wsl.conf`

Recommended secure baseline:

`.wslconfig`
```ini
[wsl2]
networkingMode=mirrored
```

`/etc/wsl.conf`
```ini
[interop]
enabled=false
appendWindowsPath=false
```

Apply in one go:

```bash
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
WSLCONFIG="/mnt/c/Users/$WIN_USER/.wslconfig"

# Ensure .wslconfig has mirrored networking under [wsl2].
if [ -f "$WSLCONFIG" ]; then
  cp "$WSLCONFIG" "${WSLCONFIG}.bak.$(date +%Y%m%d%H%M%S)"
fi
tmp=$(mktemp)
awk '
  BEGIN { in_wsl2=0; wrote=0 }
  /^\[wsl2\]$/ { in_wsl2=1; print; next }
  /^\[/ {
    if (in_wsl2 && !wrote) { print "networkingMode=mirrored"; wrote=1 }
    in_wsl2=0
  }
  {
    if (in_wsl2 && /^networkingMode=/) {
      if (!wrote) { print "networkingMode=mirrored"; wrote=1 }
      next
    }
    print
  }
  END {
    if (!in_wsl2 && !wrote) {
      print ""
      print "[wsl2]"
      print "networkingMode=mirrored"
    } else if (in_wsl2 && !wrote) {
      print "networkingMode=mirrored"
    }
  }
' "$WSLCONFIG" 2>/dev/null > "$tmp" || printf '[wsl2]\nnetworkingMode=mirrored\n' > "$tmp"
install -m 644 "$tmp" "$WSLCONFIG"
rm -f "$tmp"

# Ensure /etc/wsl.conf has interop lockdown.
sudo cp /etc/wsl.conf /etc/wsl.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true
tmp=$(mktemp)
if [ -f /etc/wsl.conf ]; then
  awk '
    BEGIN { skip=0 }
    /^\[interop\]$/ { skip=1; next }
    skip && /^\[/ { skip=0 }
    !skip { print }
  ' /etc/wsl.conf > "$tmp"
else
  : > "$tmp"
fi
printf '\n[interop]\nenabled=false\nappendWindowsPath=false\n' >> "$tmp"
sudo install -m 644 "$tmp" /etc/wsl.conf
rm -f "$tmp"
```

### Step 3: Restart once

Ask the user to run from a Windows terminal:

```bash
wsl --shutdown
```

Then reopen WSL.

### Step 4: Validate after restart

```bash
unalias adb 2>/dev/null || true
adb kill-server && adb devices
adb shell getprop sys.boot_completed
cmd.exe /c "echo should-fail" 2>/dev/null && echo "Interop still enabled" || echo "Interop disabled"
```

Expected:
- `adb devices` shows `emulator-5554  device`
- boot property returns `1`
- `cmd.exe` is not callable

---

## Troubleshooting

### `adb devices` still shows nothing after mirrored networking

- Confirm the emulator is actually running on Windows (`adb.exe devices` from a Windows terminal)
- The Windows-side adb server may need to be running: open Windows terminal, run `adb start-server`
- With mirrored networking, WSL2 `localhost` = Windows `localhost`, so `adb` in WSL2 finds the Windows adb server at `localhost:5037`
- Try: `adb kill-server && adb devices` — this forces WSL2 adb to connect to the existing Windows server rather than starting its own

### Emulator connects then drops

- Two competing adb servers (Windows and WSL2) may be fighting. Kill both:
  - Windows: `adb.exe kill-server`
  - WSL2: `adb kill-server`
  - Then restart from Windows: `adb.exe start-server` OR just run `adb devices` from WSL2 (it will connect to the Windows server via mirrored localhost)

### `.wslconfig` location

The file lives in the Windows user's home directory: `C:\Users\<username>\.wslconfig`. From WSL2 this is `/mnt/c/Users/<username>/.wslconfig`. Find the Windows username with:
```bash
cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n'
```

### Mirrored networking not available

Requires WSL2 version ≥ 2.0.0 (released with Windows 11 22H2, September 2022). Check:
```bash
wsl.exe --version 2>/dev/null || echo "Check WSL version in Windows: wsl --version"
```
If too old, upgrade WSL2: `wsl --update` from Windows PowerShell.

---

## Validation Checklist

After setup, confirm all of these pass:

- [ ] `adb devices` from WSL2 shows `emulator-XXXX  device` (no bridge, no `.exe`)
- [ ] `adb shell getprop sys.boot_completed` returns `1`
- [ ] `adb shell` is interactive
- [ ] No `ADB_SERVER_SOCKET` env var needed
- [ ] Agent (Claude yolo mode) can run `adb` commands without special configuration
- [ ] `/etc/wsl.conf` contains `[interop]`, `enabled=false`, `appendWindowsPath=false`
- [ ] After `wsl --shutdown`, `cmd.exe` is not callable from WSL

---

## What to Update After Setup

Once validated, update `AGENTS.md` in the project root with the confirmed ADB approach so future sessions don't re-investigate. The correct entry for a mirrored networking setup:

```markdown
### WSL2 + Host Emulator (mirrored networking)
- WSL2 configured with `networkingMode=mirrored` — plain `adb` works from WSL2
- No bridge, no `.exe` calls, no `ADB_SERVER_SOCKET` needed
- `adb devices` → `emulator-5554  device`
- Do NOT start a local WSL2 emulator — emulator runs on Windows host
```
