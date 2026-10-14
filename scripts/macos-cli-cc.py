#!/usr/bin/env python3
"""MoonBit linker adapter: embed a macOS app resource before final signing."""
import os
from pathlib import Path
import sys

args = sys.argv[1:]
payload = os.environ.get("DSH_MACOS_DESKTOP_PAYLOAD")
if payload:
    path = Path(payload)
    if sys.platform != "darwin" or not path.is_absolute() or not path.is_file():
        raise SystemExit("DSH_MACOS_DESKTOP_PAYLOAD must name an absolute macOS payload file")
    if "-c" not in args:
        args += ["-Xlinker", "-sectcreate", "-Xlinker", "__DSH", "-Xlinker", "__app_zip", "-Xlinker", str(path),
                 "-Xlinker", "-segprot", "-Xlinker", "__DSH", "-Xlinker", "r", "-Xlinker", "r"]
os.execv("/usr/bin/cc", ["cc", *args])
