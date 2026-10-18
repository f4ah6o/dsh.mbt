#!/usr/bin/env python3
"""Windows x64 native runtime smoke gate.

Exercises the bounded Windows profile end to end with a real dsh.exe:

  * a demo turn that creates native-demo.txt through the approval path,
  * a prune-session reopen that must not replay the approved write,
  * a loopback `dsh web --demo --port 0` request,
  * fail-closed rejection of POSIX-only host capabilities with no data
    directory mutation.

The script prints PASS/FAIL lines and exits non-zero on the first failure. It
is intentionally dependency-free so the Windows CI job can run it with the
system Python.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_EXE = REPO_ROOT / "_build" / "native" / "debug" / "build" / "cmd" / "dsh" / "dsh.exe"
DEMO_PROMPT = "Create and verify a durable file."
DEMO_FILE = "native-demo.txt"
DEMO_CONTENT = "durable native tool result"


def log_pass(message: str) -> None:
    print(f"PASS: {message}", flush=True)


def log_info(message: str) -> None:
    print(f"INFO: {message}", flush=True)


def fail(message: str) -> "NoReturn":
    print(f"FAIL: {message}", flush=True)
    raise SystemExit(1)


def run(exe: Path, args: list[str], timeout: float = 180.0) -> subprocess.CompletedProcess[str]:
    log_info("run: " + " ".join([str(exe), *args]))
    try:
        return subprocess.run(
            [str(exe), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
    except subprocess.TimeoutExpired as error:
        fail(f"command timed out after {timeout}s: {' '.join(args)} ({error})")


def last_json_object(stdout: str) -> dict:
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    fail("command did not print a JSON object: " + stdout[-2000:])


def check_demo(exe: Path, workspace: Path, data: Path) -> str:
    result = run(
        exe,
        [
            "run",
            DEMO_PROMPT,
            "--demo",
            "--approve-writes",
            "--json",
            "--data-dir",
            str(data),
            "--workspace",
            str(workspace),
        ],
    )
    if result.returncode != 0:
        fail(f"demo run exited {result.returncode}: {result.stderr.strip()}")
    session = last_json_object(result.stdout)
    if session.get("status") != "completed":
        fail(f"demo session status is {session.get('status')!r}, expected 'completed'")
    target = workspace / DEMO_FILE
    if not target.is_file():
        fail(f"{DEMO_FILE} was not created in {workspace}")
    if target.read_text(encoding="utf-8") != DEMO_CONTENT:
        fail(f"{DEMO_FILE} content mismatch")
    events = session.get("events") or []
    if not any(event.get("type") == "tool/approval/resolved" for event in events):
        fail("demo run did not resolve the write approval")
    session_id = session.get("id")
    if not isinstance(session_id, str) or not session_id.startswith("session-"):
        fail(f"demo run returned an invalid session id: {session_id!r}")
    if (data / "siwc-auth.json").exists():
        fail("Windows profile must not write siwc-auth.json")
    log_pass("demo turn completed with an approved workspace write")
    return session_id


def check_prune(exe: Path, workspace: Path, data: Path, session_id: str) -> None:
    sessions_path = data / "sessions.json"
    if not sessions_path.is_file():
        fail(f"missing durable snapshot at {sessions_path}")
    snapshot = sessions_path.read_text(encoding="utf-8")
    if session_id not in snapshot:
        fail("durable snapshot does not contain the completed session")
    target = workspace / DEMO_FILE
    before = (target.stat().st_size, target.stat().st_mtime_ns)
    result = run(
        exe,
        [
            "prune-session",
            session_id,
            "--json",
            "--data-dir",
            str(data),
            "--workspace",
            str(workspace),
        ],
    )
    if result.returncode != 0:
        fail(f"prune-session exited {result.returncode}: {result.stderr.strip()}")
    payload = last_json_object(result.stdout)
    if payload.get("session", {}).get("id") != session_id:
        fail("prune-session did not reload the expected session")
    after = (target.stat().st_size, target.stat().st_mtime_ns)
    if before != after:
        fail("prune-session replayed the approved workspace write")
    if (data / "host.lock").exists():
        fail("host.lock was left behind after prune-session")
    log_pass("prune-session reopened the store without replaying effects")


def stop_process(process: subprocess.Popen) -> bool:
    """Stop a service child, returning True when it shut down gracefully."""
    if process.poll() is None:
        try:
            os.kill(process.pid, signal.CTRL_BREAK_EVENT)
        except OSError:
            # No attached console (headless agent): fall back to a hard kill
            # and let the caller verify stale-lock recovery.
            pass
    try:
        process.wait(timeout=20)
        return process.returncode == 0
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
        return False


def check_web(exe: Path, workspace: Path, data: Path) -> None:
    log_info("starting dsh web --demo --port 0")
    process = subprocess.Popen(
        [
            str(exe),
            "web",
            "--demo",
            "--port",
            "0",
            "--data-dir",
            str(data),
            "--workspace",
            str(workspace),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
    )
    url = None
    deadline = time.monotonic() + 90.0
    assert process.stdout is not None
    try:
        while time.monotonic() < deadline:
            line = process.stdout.readline()
            if line == "":
                if process.poll() is not None:
                    break
                continue
            match = re.search(r"https?://[^\s]+", line)
            if match:
                url = match.group(0)
                break
        if url is None:
            fail("dsh web did not report a loopback URL")
        with urllib.request.urlopen(url, timeout=15) as response:
            body = response.read()
            status = response.status
        if status != 200:
            fail(f"dsh web returned HTTP {status}")
        if not body:
            fail("dsh web returned an empty body")
        log_pass(f"dsh web served HTTP 200 from {url} ({len(body)} bytes)")
    except BaseException:
        stop_process(process)
        raise

    graceful = stop_process(process)
    if graceful:
        if (data / "host.lock").exists():
            fail("host.lock was left behind after graceful dsh web shutdown")
        log_pass("dsh web shut down gracefully on CTRL_BREAK")
    else:
        log_info("console control event unavailable; verifying stale-lock recovery")
        recovery = run(
            exe,
            ["--auth-status", "--data-dir", str(data), "--workspace", str(workspace)],
        )
        if recovery.returncode != 0:
            fail(
                "stale host.lock blocked the next start: " + recovery.stderr.strip()
            )
        if (data / "host.lock").exists():
            fail("host.lock survived stale-lock recovery")
        log_pass("abrupt web exit left a recoverable host.lock, reclaimed on reopen")


def check_fail_closed(exe: Path, root: Path) -> None:
    workspace = root / "workspace"
    workspace.mkdir(parents=True, exist_ok=True)
    cases = [
        ("shell", ["run", "hi", "--demo", "--allow-shell"]),
        ("mcp-config", ["run", "hi", "--demo", "--mcp-config", str(root / "mcp.json")]),
        ("lsp-config", ["run", "hi", "--demo", "--lsp-config", str(root / "lsp.json")]),
        ("hooks-config", ["run", "hi", "--demo", "--hooks-config", str(root / "hooks.json")]),
        ("subagents", ["run", "hi", "--demo", "--enable-subagents"]),
        ("mcp", ["mcp", "--demo"]),
        ("acp", ["acp", "--demo"]),
    ]
    for name, extra in cases:
        data = root / f"data-{name}"
        result = run(exe, [*extra, "--data-dir", str(data), "--workspace", str(workspace)])
        if result.returncode == 0:
            fail(f"{name} unexpectedly succeeded on the Windows profile")
        message = (result.stderr or "") + (result.stdout or "")
        if "Windows native profile" not in message:
            fail(f"{name} failed without the Windows profile diagnostic: {message.strip()}")
        if data.exists():
            fail(f"{name} mutated the data directory before failing closed")
    log_pass("unsupported options and subcommands fail closed without mutation")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE, help="path to dsh.exe")
    parser.add_argument("--keep", action="store_true", help="keep the temporary workspace")
    arguments = parser.parse_args()
    exe = arguments.exe.resolve()
    if not exe.is_file():
        fail(f"dsh.exe not found at {exe}; build with `moon build --target native cmd/dsh`")
    if sys.platform != "win32":
        fail("this gate runs on Windows only")
    root = Path(tempfile.mkdtemp(prefix="dsh-windows-runtime-"))
    workspace = root / "workspace"
    workspace.mkdir()
    data = root / "data"
    try:
        session_id = check_demo(exe, workspace, data)
        check_prune(exe, workspace, data, session_id)
        check_web(exe, workspace, root / "web-data")
        check_fail_closed(exe, root / "gates")
        log_pass("Windows native runtime smoke gate completed")
        return 0
    finally:
        if arguments.keep:
            log_info(f"kept temporary directory {root}")
        else:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
