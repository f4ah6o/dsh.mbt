#!/usr/bin/env python3
"""Windows GPUI desktop gate.

Builds (or reuses) the release desktop executable and checks the observable
evidence of a real window:

  * `--smoke` presents a frame, resizes, closes, and prints its marker,
  * `--offline-e2e` (with GPUI_NATIVE_E2E=1) sends the demo prompt, approves the
    write, completes, reloads the session, checks the Japanese frame, and writes
    a PPM plus a settings-frame PPM,
  * the workspace write exists and the data directory contains a durable
    session snapshot but no credential file.

The PPM checks are structural (magic, dimensions, non-uniform pixels); the
pixel-accurate Japanese/settings assertions run inside the app against its own
owned frame.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
RELEASE_DESKTOP = REPO_ROOT / "_build" / "native" / "release" / "build" / "desktop" / "windows" / "windows.exe"
RELEASE_CLI = REPO_ROOT / "_build" / "native" / "release" / "build" / "cmd" / "dsh" / "dsh.exe"


def fail(message: str) -> "NoReturn":
    print(f"FAIL: {message}", flush=True)
    raise SystemExit(1)


def info(message: str) -> None:
    print(f"INFO: {message}", flush=True)


def passed(message: str) -> None:
    print(f"PASS: {message}", flush=True)


def run(command: list[str], env: dict[str, str] | None = None, timeout: float = 300.0) -> subprocess.CompletedProcess[str]:
    info("run: " + " ".join(command))
    try:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired as error:
        fail(f"command timed out: {error}")


def marker(lines: list[str], prefix: str) -> dict:
    for line in reversed(lines):
        if line.startswith(prefix):
            try:
                return json.loads(line[len(prefix):].strip())
            except json.JSONDecodeError:
                continue
    fail(f"missing {prefix} marker in output:\n" + "\n".join(lines[-20:]))


def check_ppm(path: Path) -> tuple[int, int]:
    if not path.is_file():
        fail(f"missing frame evidence at {path}")
    with path.open("rb") as handle:
        header = handle.read(32)
        body = handle.read()
    if not header.startswith(b"P6"):
        fail(f"{path} is not a binary PPM (P6)")
    parts = header.split()
    width, height = int(parts[1]), int(parts[2])
    if width < 100 or height < 100:
        fail(f"{path} has an implausible size {width}x{height}")
    if len(body) < width * height:
        fail(f"{path} is truncated")
    colors = set(body[: min(len(body), 65536)])
    if len(colors) < 4:
        fail(f"{path} is a blank frame")
    return width, height


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desktop", type=Path, default=RELEASE_DESKTOP)
    parser.add_argument("--cli", type=Path, default=RELEASE_CLI)
    parser.add_argument("--keep", action="store_true")
    parser.add_argument("--no-build", action="store_true", help="reuse existing executables")
    arguments = parser.parse_args()
    if sys.platform != "win32":
        fail("this gate runs on Windows only")
    desktop = arguments.desktop.resolve()
    cli = arguments.cli.resolve()
    if not arguments.no_build:
        build = run(["moon", "build", "--target", "native", "--release", "desktop/windows", "cmd/dsh"])
        if build.returncode != 0:
            fail("moon build failed: " + build.stderr.strip())
    if not desktop.is_file():
        fail(f"desktop executable not built: {desktop}")
    if not cli.is_file():
        fail(f"CLI executable not built: {cli}")

    root = Path(tempfile.mkdtemp(prefix="dsh-windows-desktop-"))
    workspace = root / "workspace"
    workspace.mkdir()
    data = root / "data"
    frame = root / "frame.ppm"
    env = dict(os.environ)
    env["DSH_NATIVE_WORKER_BIN"] = str(cli)
    env.pop("GPUI_NATIVE_E2E", None)
    try:
        smoke = run([str(desktop), "--smoke", "--workspace", str(workspace), "--data-dir", str(data)], env=env)
        if smoke.returncode != 0:
            fail("smoke failed: " + smoke.stderr.strip())
        output = (smoke.stdout + smoke.stderr).splitlines()
        payload = marker(output, "DSH_DESKTOP_SMOKE")
        if not all(payload.get(key) is True for key in ("frame", "resized", "close_requested", "destroyed")):
            fail(f"smoke marker is incomplete: {payload}")
        passed("smoke presented, resized, closed and destroyed the window")

        e2e_env = dict(env)
        e2e_env["GPUI_NATIVE_E2E"] = "1"
        e2e = run(
            [
                str(desktop),
                "--offline-e2e",
                "--workspace",
                str(workspace),
                "--data-dir",
                str(data),
                "--frame-output",
                str(frame),
            ],
            env=e2e_env,
        )
        if e2e.returncode != 0:
            fail("offline E2E failed: " + e2e.stderr.strip())
        lines = (e2e.stdout + e2e.stderr).splitlines()
        demo = marker(lines, "DSH_DESKTOP_DEMO")
        for key in ("native_events", "tool_approval", "completed", "workspace_write", "reload", "japanese_frame"):
            if demo.get(key) not in (True, "approved", "passed"):
                fail(f"E2E marker {key} is {demo.get(key)!r}")
        passed("demo send / approval / workspace write / reload completed")

        written = workspace / "native-demo.txt"
        if not written.is_file():
            fail("workspace write is missing")
        width, height = check_ppm(frame)
        passed(f"frame evidence is a {width}x{height} PPM with non-uniform pixels")
        settings = Path(str(frame) + ".settings.ppm")
        settings_width, settings_height = check_ppm(settings)
        passed(f"settings frame evidence is a {settings_width}x{settings_height} PPM")
        snapshot = data / "sessions.json"
        if not snapshot.is_file():
            fail("durable sessions.json is missing")
        if (data / "siwc-auth.json").exists():
            fail("Windows profile must not write siwc-auth.json")
        passed("durable session snapshot exists and no credential file was written")
        return 0
    finally:
        if arguments.keep:
            info(f"kept {root}")
        else:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
