#!/usr/bin/env python3
"""Reject a macOS app whose Mach-O minimum exceeds its plist promise."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def parse_version(value: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        fail(f"invalid macOS deployment version: {value!r}")
    return tuple(int(part) for part in value.split("."))


def padded(version: tuple[int, ...]) -> tuple[int, int, int]:
    return (version + (0, 0, 0))[:3]


def declared_macho_minimum(binary: Path) -> str:
    try:
        output = subprocess.run(
            ["otool", "-l", str(binary)],
            check=True,
            text=True,
            capture_output=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"could not inspect Mach-O deployment target for {binary}: {error}")

    minimums: list[str] = []
    for block in re.split(r"(?m)^Load command \d+\s*$", output):
        command = re.search(r"(?m)^\s*cmd\s+(\S+)\s*$", block)
        if command is None:
            continue
        if command.group(1) == "LC_BUILD_VERSION":
            minimum = re.search(r"(?m)^\s*minos\s+(\S+)\s*$", block)
        elif command.group(1) == "LC_VERSION_MIN_MACOSX":
            minimum = re.search(r"(?m)^\s*version\s+(\S+)\s*$", block)
        else:
            continue
        if minimum is not None:
            minimums.append(minimum.group(1))

    if not minimums:
        fail(f"{binary} has no LC_BUILD_VERSION or LC_VERSION_MIN_MACOSX target")
    parsed = [(padded(parse_version(value)), value) for value in minimums]
    parsed.sort(key=lambda item: item[0])
    return parsed[-1][1]


def main() -> None:
    if len(sys.argv) < 3:
        fail("usage: check-macos-deployment-target.py APP_BUNDLE MACHO [MACHO ...]")

    app = Path(sys.argv[1])
    binaries = [Path(value) for value in sys.argv[2:]]
    try:
        declared = subprocess.run(
            [
                "/usr/libexec/PlistBuddy",
                "-c",
                "Print :LSMinimumSystemVersion",
                str(app / "Contents/Info.plist"),
            ],
            check=True,
            text=True,
            capture_output=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"could not read LSMinimumSystemVersion from {app}: {error}")

    declared_version = padded(parse_version(declared))
    for binary in binaries:
        minimum = declared_macho_minimum(binary)
        if padded(parse_version(minimum)) > declared_version:
            fail(
                f"{binary} requires macOS {minimum}, newer than the app's "
                f"LSMinimumSystemVersion {declared}"
            )
        print(f"{binary}: macOS {minimum} (app minimum {declared})")


if __name__ == "__main__":
    main()
