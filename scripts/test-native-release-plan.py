#!/usr/bin/env python3
"""Regression checks for release scope and fail-closed asset publication."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("release_plan", Path(__file__).with_name("native-release-plan.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleasePlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dsh-release-plan-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / ".github").mkdir()
        (self.root / "docs/releases").mkdir(parents=True)
        (self.root / "moon.mod").write_text('name = "fixture/release"\nversion = "0.1.25"\n')
        (self.root / "docs/releases/0.1.25.md").write_text("macOS artifacts only; other operating systems are not qualified.\n")
        self.configure("0.1.25", ["darwin-aarch64"])

    def configure(self, version, platforms):
        (self.root / ".github/native-release.json").write_text(json.dumps({"version": version, "platforms": platforms}))

    def test_macos_tag_has_no_linux_build_or_asset(self):
        plan = release.build_plan(self.root, "push", "v0.1.25")
        self.assertEqual(plan["matrix"]["include"], [{"os": "macos-15", "platform": "darwin-aarch64"}])
        self.assertEqual(plan["assets"], ["dsh-darwin-aarch64", "Dsh-macos-arm64.zip"])

    def test_regular_pr_still_validates_every_platform(self):
        plan = release.build_plan(self.root, "pull_request", "99/merge")
        self.assertEqual({p["platform"] for p in plan["matrix"]["include"]}, set(release.PLATFORMS))
        self.assertEqual(len(plan["assets"]), 5)
        self.assertIn("dsh-windows-x86_64.zip", plan["assets"])

    def test_windows_tag_ships_a_zip_asset(self):
        self.configure("0.1.25", ["windows-x86_64"])
        plan = release.build_plan(self.root, "push", "v0.1.25")
        self.assertEqual(plan["matrix"]["include"], [{"os": "windows-latest", "platform": "windows-x86_64"}])
        self.assertEqual(plan["assets"], ["dsh-windows-x86_64.zip"])

    def test_version_and_tag_must_match(self):
        with self.assertRaises(ValueError):
            release.build_plan(self.root, "push", "v0.1.26")
        self.configure("0.1.24", ["darwin-aarch64"])
        with self.assertRaises(ValueError):
            release.build_plan(self.root, "push", "v0.1.25")

    def test_invalid_scope_and_missing_notes_fail_closed(self):
        for platforms in [[], ["solaris-x86_64"], ["darwin-aarch64", "darwin-aarch64"]]:
            self.configure("0.1.25", platforms)
            with self.assertRaises(ValueError):
                release.build_plan(self.root, "push", "v0.1.25")
        self.configure("0.1.25", ["darwin-aarch64"])
        (self.root / "docs/releases/0.1.25.md").unlink()
        with self.assertRaises(ValueError):
            release.build_plan(self.root, "push", "v0.1.25")

    def test_missing_extra_empty_or_symlink_assets_cannot_publish(self):
        assets = self.root / "release"
        assets.mkdir()
        expected = ["dsh-darwin-aarch64", "Dsh-macos-arm64.zip"]
        for name in expected:
            (assets / name).write_bytes(b"synthetic artifact")
        release.verify_assets(assets, expected)
        extra = assets / "dsh-linux-x86_64"
        extra.write_bytes(b"must not silently include an unqualified OS")
        with self.assertRaises(ValueError):
            release.verify_assets(assets, expected)
        extra.unlink()
        target = assets / expected[0]
        target.write_bytes(b"")
        with self.assertRaises(ValueError):
            release.verify_assets(assets, expected)
        target.unlink()
        with self.assertRaises(ValueError):
            release.verify_assets(assets, expected)
        target.symlink_to(assets / expected[1])
        with self.assertRaises(ValueError):
            release.verify_assets(assets, expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)
