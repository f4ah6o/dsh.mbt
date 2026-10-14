#!/usr/bin/env python3
"""Headless process tests for packaging/extraction. No display or socket needed."""
import importlib.util
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import time
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("packager", ROOT / "scripts/package-linux-desktop.py")
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)

HARNESS = r'''
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
int dsh_linux_desktop_launch(const unsigned char *, int);
int main(int argc, char **argv) {
  if (argc > 1 && !strcmp(argv[1], "--helper-probe")) { puts("helper-ok"); return 0; }
  const char *explicit_path = getenv("TEST_APP_PATH");
  size_t prefix = explicit_path ? strlen(explicit_path) + 1 : 1;
  size_t n = prefix; for (int i = 1; i < argc; i++) n += strlen(argv[i]) + 1;
  char *p = calloc(n, 1), *c = p + prefix;
  if (explicit_path) strcpy(p, explicit_path);
  for (int i = 1; i < argc; i++) { strcpy(c, argv[i]); c += strlen(c) + 1; }
  int status = dsh_linux_desktop_launch((unsigned char *)p, (int)n);
  free(p); if (status < 0) { fprintf(stderr, "error=%d\n", status); return 100 - status; }
  return status;
}
'''
GUI = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/wait.h>
int main(int argc, char **argv) {
  const char *helper = getenv("DSH_NATIVE_WORKER_BIN");
  struct stat st; if (!helper || stat(helper, &st) || (st.st_mode & 0777) != 0700) return 88;
  printf("helper=%s\n", helper);
  for (int i = 1; i < argc; i++) printf("arg=%s\n", argv[i]);
  fflush(stdout);
  if (argc > 1 && !strcmp(argv[1], "--wait")) { while (1) pause(); }
  const char *original = getenv("TEST_UNLINK_ORIGINAL");
  if (original && unlink(original)) return 91;
  pid_t p = fork(); if (!p) { execl(helper, helper, "--helper-probe", NULL); _exit(89); }
  int s; waitpid(p, &s, 0); if (s) return 90;
  return 37;
}
'''


class PayloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dsh-payload-test-")
        self.dir = Path(self.temp.name)
        self.extract = self.dir / "temp space"
        self.extract.mkdir()
        self.env = dict(os.environ, TMPDIR=str(self.extract), DSH_NATIVE_WORKER_BIN="/wrong/old/helper")
        self.cli = self.dir / "cli"
        self.gui = self.dir / "gui"
        self.output = self.dir / "packaged"
        for name, code in (("cli", HARNESS), ("gui", GUI)):
            source = self.dir / (name + ".c")
            source.write_text(code)
            cmd = ["cc", "-Wall", "-Wextra", "-Werror", str(source)]
            if name == "cli":
                cmd += [str(ROOT / "runtime/linux_desktop_payload.c")]
            subprocess.run(cmd + ["-o", str(self.dir / name)], check=True)
        packager.package(self.cli, self.gui, self.output)

    def tearDown(self):
        self.temp.cleanup()

    def run_payload(self, *args):
        return subprocess.run([str(self.output), *args], env=self.env, text=True, capture_output=True, timeout=10)

    def assert_clean(self):
        self.assertEqual(list(self.extract.iterdir()), [])

    def test_single_file_arguments_exit_helper_and_cleanup(self):
        self.gui.unlink()
        result = self.run_payload("two words", "", "$(touch nope)", "--flag", "雪")
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertIn("arg=two words\narg=\narg=$(touch nope)\narg=--flag\narg=雪\n", result.stdout)
        self.assertIn("helper-ok", result.stdout)
        self.assert_clean()

    def test_corrupt_and_malformed_payloads(self):
        original = self.output.read_bytes()
        variants = []
        corrupted = bytearray(original); corrupted[len(self.cli.read_bytes()) + 100] ^= 1; variants.append(corrupted)
        for offset, value in ((16, 2), (20, 1)):
            data = bytearray(original); struct.pack_into("<I", data, len(data) - 40 + offset, value); variants.append(data)
        for value in (0, 2**64 - 1, packager.MAX_PAYLOAD + 1):
            data = bytearray(original); struct.pack_into("<Q", data, len(data) - 16, value); variants.append(data)
        variants.append(original[:-1])
        for data in variants:
            self.output.write_bytes(data)
            result = self.run_payload()
            self.assertNotEqual(result.returncode, 37)
            self.assert_clean()

    def test_unbundled_missing_payload(self):
        result = subprocess.run([str(self.cli)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 101)
        self.assert_clean()

    def test_packager_rejects_invalid_arch_and_double_packaging(self):
        with self.assertRaises(ValueError):
            packager.package(self.output, self.gui, self.dir / "double")
        data = bytearray(self.gui.read_bytes()); data[18] ^= 1; self.gui.write_bytes(data)
        with self.assertRaises(ValueError):
            packager.package(self.cli, self.gui, self.dir / "bad")

    def test_signal_forwards_and_cleans(self):
        for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT):
            process = subprocess.Popen([str(self.output), "--wait"], env=self.env, text=True, stdout=subprocess.PIPE)
            try:
                line = process.stdout.readline()
                helper = Path(line.removeprefix("helper=").strip())
                self.assertTrue(helper.is_file())
                self.assertEqual(helper.parent.stat().st_mode & 0o777, 0o700)
                process.send_signal(sig)
                self.assertEqual(process.wait(timeout=10), 128 + sig)
                self.assert_clean()
            finally:
                if process.poll() is None: process.kill(); process.wait()
                process.stdout.close()

    def test_helper_survives_original_removal_and_symlink_launch(self):
        link = self.dir / "launch link"
        link.symlink_to(self.output)
        self.env["TEST_UNLINK_ORIGINAL"] = str(self.output)
        result = subprocess.run([str(link)], env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertIn("helper-ok", result.stdout)
        self.assertFalse(self.output.exists())
        self.assert_clean()

    def test_explicit_app_and_permission_error(self):
        self.env["TEST_APP_PATH"] = str(self.gui)
        result = subprocess.run([str(self.cli), "two words"], env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 37, result.stderr)
        self.gui.chmod(0o600)
        result = subprocess.run([str(self.cli)], env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 104)
        self.assert_clean()

    def test_noexec_temporary_directory(self):
        mount = Path("/dev/shm")
        if not mount.is_dir() or not (os.statvfs(mount).f_flag & os.ST_NOEXEC):
            self.skipTest("no preexisting noexec temporary filesystem")
        with tempfile.TemporaryDirectory(prefix="dsh-noexec-", dir=mount) as directory:
            self.env["TMPDIR"] = directory
            result = self.run_payload()
            self.assertEqual(result.returncode, 104, result.stderr)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_missing_temp_directory_and_cleanup(self):
        # Explicit nonexistent TMPDIR is deterministic and does not require mounts.
        self.env["TMPDIR"] = str(self.dir / "missing")
        result = self.run_payload()
        self.assertEqual(result.returncode, 103)
        self.assert_clean()


class ActualCliTests(unittest.TestCase):
    def setUp(self):
        configured = os.environ.get("DSH_LINUX_DESKTOP_CLI")
        if not configured:
            self.skipTest("set DSH_LINUX_DESKTOP_CLI to test the actual MoonBit CLI signal runtime")
        self.cli = Path(configured)
        self.assertTrue(self.cli.is_absolute() and self.cli.is_file(), "DSH_LINUX_DESKTOP_CLI must be an absolute built CLI path")
        self.temp = tempfile.TemporaryDirectory(prefix="dsh-actual-cli-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.extraction = self.root / "extraction"
        self.extraction.mkdir()
        self.env = dict(os.environ, TMPDIR=str(self.extraction))

    def test_actual_cli_rejects_malformed_arguments(self):
        for args, diagnostic in ((["--app-path"], "requires a nonempty absolute path"),
                                 (["--app-path", "relative"], "must be an absolute path")):
            result = subprocess.run([str(self.cli), "desktop", *args], env=self.env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertIn(diagnostic, result.stderr)
            self.assertEqual(list(self.extraction.iterdir()), [])

    def test_actual_cli_sigterm_reaps_child_and_cleans(self):
        ready = self.root / "ready"
        self.env["TEST_READY"] = str(ready)
        script = ("sleep 60 & child=$!; "
                  "trap 'kill \"$child\" 2>/dev/null; wait \"$child\" 2>/dev/null; exit 0' TERM; "
                  "printf '%s %s\\n' \"$$\" \"$child\" > \"$TEST_READY\"; "
                  "wait \"$child\"")
        process = subprocess.Popen([str(self.cli), "desktop", "--app-path", "/bin/sh", "--", "-c", script],
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        owned_pids = []
        try:
            deadline = time.monotonic() + 10
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(ready.exists(), "actual CLI child did not become ready")
            owned_pids = [int(value) for value in ready.read_text().split()]
            self.assertEqual(len(owned_pids), 2)
            self.assertTrue(list(self.extraction.iterdir()), "launcher did not create its private helper directory")
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 143, f"stdout={stdout!r} stderr={stderr!r}")
            self.assertEqual(list(self.extraction.iterdir()), [])
            for pid in owned_pids:
                with self.assertRaises(ProcessLookupError, msg=f"desktop descendant {pid} survived SIGTERM"):
                    os.kill(pid, 0)
            owned_pids = []
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            # Only processes created by this fixture are eligible for cleanup.
            for pid in owned_pids:
                try: os.kill(pid, signal.SIGKILL)
                except ProcessLookupError: pass
            process.stdout.close()
            process.stderr.close()


if __name__ == "__main__":
    unittest.main()
