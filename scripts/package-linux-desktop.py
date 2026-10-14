#!/usr/bin/env python3
"""Append the native Linux companion to a CLI ELF; no runtime downloads.

The versioned footer and FNV-1a checksum detect accidental corruption, not
malicious replacement. Authenticate the complete release through distribution.
"""
import argparse
import os
from pathlib import Path
import struct
import tempfile

MAGIC = b"DSH-LINUX-GUI\0\0\0"
FOOTER = struct.Struct("<16sIIQQ")
MAX_PAYLOAD = 512 * 1024 * 1024


def checksum(data):
    value = 14695981039346656037
    for byte in data:
        value = ((value ^ byte) * 1099511628211) & 0xffffffffffffffff
    return value


def package(cli, desktop, output):
    base, payload = Path(cli).read_bytes(), Path(desktop).read_bytes()
    for label, data in (("CLI", base), ("desktop", payload)):
        if len(data) < 20 or data[:4] != b"\x7fELF":
            raise ValueError(f"{label} must be an ELF executable")
    if base[4:6] != payload[4:6] or base[18:20] != payload[18:20]:
        raise ValueError("CLI and desktop ELF architectures must match")
    if not 4 <= len(payload) <= MAX_PAYLOAD:
        raise ValueError("desktop payload exceeds supported size")
    if len(base) >= FOOTER.size and base[-FOOTER.size:][:16] == MAGIC:
        raise ValueError("CLI already contains a desktop payload; use the original CLI")
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".dsh-package-", dir=output.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(base)
            stream.write(payload)
            stream.write(FOOTER.pack(MAGIC, 1, 0, len(payload), checksum(payload)))
            stream.flush()
            os.fchmod(stream.fileno(), 0o755)
            os.fsync(stream.fileno())
        os.replace(temp, output)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", required=True)
    parser.add_argument("--desktop", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        package(args.cli, args.desktop, args.output)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Linux desktop packaging failed: {error}\n")
