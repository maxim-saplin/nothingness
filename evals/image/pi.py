#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import sys


def main() -> int:
    environment = os.environ.copy()
    environment["PI_SKIP_VERSION_CHECK"] = "1"
    return subprocess.run(["node", "/opt/pi/bin/pi", *sys.argv[1:]], env=environment).returncode


if __name__ == "__main__":
    raise SystemExit(main())