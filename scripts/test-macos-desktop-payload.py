#!/usr/bin/env python3
"""Synthetic macOS packaging tests. No installed app or user workspace is used."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "runtime/macos_desktop_payload.c"
PRODUCER = ROOT / "scripts/prepare-macos-desktop-payload.py"
spec = importlib.util.spec_from_file_location("macos_payload", PRODUCER)
producer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(producer)

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True, **kwargs)

def envelope(data, version="0.1.24"):
    version = version.encode()
    return struct.pack("<16sIIQ32sII", producer.MAGIC, 2, len(version), len(data), hashlib.sha256(data).digest(), 4, 0) + version + struct.pack("<I", 0) + data

@unittest.skipUnless(sys.platform == "darwin", "macOS packaging primitive")
class PayloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="dsh-macos-payload-test-")
        cls.root = Path(cls.temp.name)
        source = cls.root / "fixture.c"
        source.write_text(r'''#include <fcntl.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
  if (argc == 3 && !strcmp(argv[1], "--marker")) {
    int fd = open(argv[2], O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (fd < 0) return 1;
    const char *text = "synthetic LaunchServices fixture\n";
    if (write(fd, text, strlen(text)) < 0) return 1;
    close(fd);
  }
  return 0;
}
''')
        cls.binary = cls.root / "base-cli"
        run("xcrun", "clang", "-mmacosx-version-min=13.0", source, "-o", cls.binary)
        run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", cls.binary)
        driver = cls.root / "driver.c"
        driver.write_text('#include "' + str(SOURCE) + '"\n' + r'''
int main(int argc, char **argv) {
  unsigned char out[4096] = {0}; int result;
  if (argc == 2) {
    result = dsh_macos_desktop_bundle((const unsigned char *)argv[1], out, sizeof(out));
  } else if (argc == 4 || (argc == 5 && !strcmp(argv[1], "--cli"))) {
    int from_cli = argc == 5;
    const char *input = argv[from_cli ? 2 : 1];
    const char *cache = argv[from_cli ? 3 : 2];
    const char *source_path = argv[from_cli ? 2 : 3];
    int fd = open(input, O_RDONLY), source = open(source_path, O_RDONLY); struct stat st;
    if (fd < 0 || source < 0 || fstat(fd, &st) || st.st_size <= 0) return 2;
    void *p = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (p == MAP_FAILED) return 2;
    const unsigned char *payload = p; size_t length = (size_t)st.st_size;
    result = from_cli ? dsh_payload_section(p, length, &payload, &length) : 1;
    if (result == 1) result = dsh_extract_bundle(payload, length, cache, source, out, sizeof(out));
    munmap(p, (size_t)st.st_size); close(fd); close(source);
  } else return 2;
  if (result == 1) puts((const char *)out); else fprintf(stderr, "payload result %d\n", result);
  return result == 1 ? 0 : (result == 0 ? 3 : 1);
}
''')
        cls.driver_source = driver
        cls.driver = cls.root / "driver"
        run("xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror", "-mmacosx-version-min=13.0", driver, "-o", cls.driver)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="case-", dir=self.root)
        self.case = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.cache = self.case / "cache"
        self.payload = self.make_payload("0.1.24")

    def make_payload(self, version):
        stage = self.case / ("stage-" + version)
        contents = stage / "Dsh-macos-arm64/Dsh.app/Contents"
        for name in ("MacOS", "Helpers", "Frameworks", "Resources"):
            (contents / name).mkdir(parents=True)
        for name in ("MacOS/dsh-desktop", "Helpers/dsh", "Frameworks/libgpui_macos.dylib"):
            shutil.copy2(self.binary, contents / name)
        (contents / "Resources/test-resource.txt").write_text("fixture resources survive extraction\n")
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "dsh-desktop", "CFBundleIdentifier": "org.fu2hito.dsh",
            "CFBundleName": "Dsh", "CFBundlePackageType": "APPL",
            "CFBundleVersion": version, "CFBundleShortVersionString": version,
            "LSBackgroundOnly": True,
        }))
        run("/usr/bin/codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", contents.parent)
        archive = self.case / (version + ".zip")
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", stage / "Dsh-macos-arm64", archive)
        payload = self.case / (version + ".payload")
        producer.prepare(archive, version, payload)
        return payload

    def extract(self, payload=None, cache=None, success=True, source=None):
        result = subprocess.run([str(self.driver), str(payload or self.payload), str(cache or self.cache), str(source or self.binary)], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return Path(result.stdout.strip()) if success else result

    def test_repeat_concurrent_and_version_upgrade(self):
        with ThreadPoolExecutor(max_workers=6) as pool:
            paths = list(pool.map(lambda _: self.extract(), range(12)))
        self.assertEqual(len(set(paths)), 1)
        self.assertEqual(self.extract(), paths[0])
        self.assertEqual((paths[0] / "Contents/Resources/test-resource.txt").read_text(), "fixture resources survive extraction\n")
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", paths[0])
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(paths[0].parents[1].stat().st_mode), 0o700)
        newer = self.extract(self.make_payload("0.1.25"))
        self.assertNotEqual(newer, paths[0])
        self.assertTrue(paths[0].exists())
        self.assertFalse(list(self.cache.glob(".stage-*")))

    def test_corruption_bounds_and_archive_paths_fail_before_extraction(self):
        valid = self.payload.read_bytes()
        for label, data in {
            "short": b"short", "truncated": valid[:-1],
            "digest": valid[:-1] + bytes([valid[-1] ^ 1]),
            "huge": valid[:24] + struct.pack("<Q", 2**63) + valid[32:],
        }.items():
            path = self.case / (label + ".payload"); path.write_bytes(data)
            self.extract(path, success=False)
            self.assertFalse(self.cache.exists())
        for index, (name, mode, extra) in enumerate([
            ("Dsh-macos-arm64/../../escape", stat.S_IFREG | 0o644, b""),
            ("/absolute", stat.S_IFREG | 0o644, b""),
            ("Dsh-macos-arm64/link", stat.S_IFLNK | 0o777, b""),
            ("Dsh-macos-arm64/override", stat.S_IFREG | 0o644, struct.pack("<HH", 0x7075, 0)),
            ("Dsh-macos-arm64/setuid", stat.S_IFREG | 0o4644, b""),
        ]):
            archive = self.case / ("bad-" + str(index) + ".zip")
            with zipfile.ZipFile(archive, "w") as z:
                info = zipfile.ZipInfo(name); info.external_attr = mode << 16; info.extra = extra
                z.writestr(info, b"unsafe")
            path = archive.with_suffix(".payload"); path.write_bytes(envelope(archive.read_bytes()))
            self.extract(path, success=False)
            self.assertFalse(self.cache.exists())
        self.assertFalse((self.case / "escape").exists())

    def test_cached_tampering_and_symlinks_fail_without_replacement(self):
        app = self.extract()
        resource = app / "Contents/Resources/test-resource.txt"
        resource.write_text("tampered")
        self.extract(success=False)
        self.assertEqual(resource.read_text(), "tampered")
        run("/usr/bin/codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", app)
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
        self.extract(success=False)
        self.assertEqual(resource.read_text(), "tampered", "even a re-signed cache must match the embedded manifest")
        other = self.case / "other"; other.mkdir(mode=0o700)
        link = self.case / "symlink-cache"; link.symlink_to(other, target_is_directory=True)
        self.extract(cache=link, success=False)
        self.assertFalse(list(other.iterdir()))

    def test_insecure_cache_or_lock_rejected(self):
        self.cache.mkdir(mode=0o755)
        self.extract(success=False)
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o755)
        self.cache.rmdir(); self.cache.mkdir(mode=0o700)
        digest = self.payload.read_bytes()[32:64].hex()
        victim = self.case / "victim"; victim.write_text("preserve")
        (self.cache / (".lock-" + digest)).symlink_to(victim)
        self.extract(success=False)
        self.assertEqual(victim.read_text(), "preserve")

    def test_quarantine_is_preserved(self):
        source = self.case / "quarantined-cli"; shutil.copy2(self.binary, source)
        value = b"0083;00000000;dsh-fixture;"
        run("/usr/bin/xattr", "-w", "com.apple.quarantine", value.decode(), source)
        app = self.extract(source=source)
        self.assertEqual(run("/usr/bin/xattr", "-p", "com.apple.quarantine", app).stdout.strip().encode(), value)
        self.assertEqual(run("/usr/bin/xattr", "-p", "com.apple.quarantine", source).stdout.strip().encode(), value)

    @unittest.skipUnless(os.environ.get("DSH_TEST_MACOS_MOON_CLI") == "1", "opt-in actual MoonBit CLI with background-only synthetic bundle")
    def test_actual_moon_cli_launches_embedded_synthetic_app(self):
        # Exercise the real MoonBit FFI, path decoding and LaunchServices argv,
        # while the payload is a tiny non-Metal app that exits on its own.
        version = re.search(r'^version = "([^"]+)"', (ROOT / "moon.mod").read_text(), re.M).group(1)
        archive = self.case / (version + ".zip")
        if not archive.exists():
            self.make_payload(version)
        cli = self.case / "synthetic-bundled-cli"
        run("/bin/sh", ROOT / "scripts/package-macos-cli.sh", archive, cli, cwd=ROOT)
        home = self.case / "isolated launch home"
        home.mkdir(mode=0o700)
        env = dict(os.environ, HOME=str(home))
        def launch(marker, override=None):
            args = [cli, "desktop"]
            if override is not None:
                args += ["--app-path", override]
            args += ["--", "--marker", marker]
            run(*args, cwd=self.case, env=env)
            deadline = time.monotonic() + 10
            while not marker.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue(marker.exists(), "the real MoonBit CLI did not launch the synthetic bundled app")
            self.assertEqual(marker.read_text(), "synthetic LaunchServices fixture\n")
        launch(self.case / "first marker")
        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(lambda i: launch(self.case / ("concurrent marker " + str(i))), range(3)))
        cache = home / "Library/Caches/org.fu2hito.dsh/bundled-desktop"
        versions = [p for p in cache.iterdir() if not p.name.startswith(".")]
        self.assertEqual(len(versions), 1)
        app = versions[0] / "Dsh-macos-arm64/Dsh.app"
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
        # The explicit override must bypass the embedded cache. An identical
        # fixture marker alone would also pass if --app-path were ignored.
        resource = app / "Contents/Resources/test-resource.txt"
        resource.write_text("invalid embedded cache must remain untouched\n")
        rejected_marker = self.case / "rejected embedded marker"
        rejected = subprocess.run([str(cli), "desktop", "--", "--marker", str(rejected_marker)], cwd=self.case, env=env, capture_output=True)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertFalse(rejected_marker.exists())
        override = self.extract(cache=self.case / "explicit override cache")
        launch(self.case / "override marker", override=override)
        self.assertEqual(resource.read_text(), "invalid embedded cache must remain untouched\n")
        self.assertFalse(list(cache.glob(".stage-*")))

    @unittest.skipUnless(os.environ.get("DSH_TEST_MACOS_LAUNCH_SERVICES") == "1", "opt-in background-only synthetic LaunchServices fixture")
    def test_repeated_concurrent_launches_and_upgrade(self):
        app = self.extract()
        def launch(pair):
            path, marker = pair
            run("/usr/bin/open", "-n", "-a", path, "--args", "--marker", marker)
            deadline = time.monotonic() + 10
            while not marker.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue(marker.exists(), "LaunchServices did not start the background-only synthetic app")
            self.assertEqual(marker.read_text(), "synthetic LaunchServices fixture\n")
        markers = [(app, self.case / ("launch-" + str(i))) for i in range(4)]
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(launch, markers))
        launch((app, self.case / "repeat"))
        newer = self.extract(self.make_payload("0.1.25"))
        launch((newer, self.case / "upgrade"))
        self.assertTrue(app.exists())

    @unittest.skipUnless(os.environ.get("DSH_MACOS_DESKTOP_CLI"), "set DSH_MACOS_DESKTOP_CLI to verify actual MoonBit release output")
    def test_actual_packaged_cli_resource(self):
        cli = Path(os.environ["DSH_MACOS_DESKTOP_CLI"]).resolve()
        run("/usr/bin/codesign", "--verify", "--strict", cli)
        result = run(self.driver, "--cli", cli, self.cache, "unused")
        app = Path(result.stdout.strip())
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
        again = run(self.driver, "--cli", cli, self.cache, "unused")
        self.assertEqual(result.stdout, again.stdout)
        helper = app / "Contents/Helpers/dsh"
        run(helper, "--help")
        absent = subprocess.run([str(self.driver), "--cli", str(helper), str(self.case / "helper-cache"), "unused"], capture_output=True)
        self.assertEqual(absent.returncode, 3, "the private helper must remain unbundled")

    def test_macho_resource_and_final_signature(self):
        wrapper = PRODUCER.parent / "macos-cli-cc.py"
        executable = self.case / "bundled-cli"
        env = dict(os.environ, DSH_MACOS_DESKTOP_PAYLOAD=str(self.payload))
        run(sys.executable, wrapper, "-std=c11", self.driver_source, "-o", executable, env=env)
        run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", executable)
        run("/usr/bin/codesign", "--verify", "--strict", executable)
        home = self.case / "home"; home.mkdir(mode=0o700)
        app = Path(run(executable, home).stdout.strip())
        self.assertTrue(str(app).startswith(str(home.resolve() / "Library/Caches/org.fu2hito.dsh/bundled-desktop")))
        self.assertEqual(Path(run(executable, home).stdout.strip()), app)
        absent = subprocess.run([str(self.driver), str(home)], capture_output=True)
        self.assertEqual(absent.returncode, 3)
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)

if __name__ == "__main__":
    unittest.main(verbosity=2)
