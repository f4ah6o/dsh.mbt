#!/usr/bin/env python3
"""Select tag release assets without narrowing ordinary pull-request gates."""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = {
    "linux-x86_64": "ubuntu-24.04",
    "linux-aarch64": "ubuntu-24.04-arm",
    "darwin-aarch64": "macos-15",
}


def build_plan(root, event, ref):
    match = re.search(r'^version = "([^"]+)"$', (root / "moon.mod").read_text(), re.M)
    if not match or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", match[1]):
        raise ValueError("moon.mod must contain one valid release version")
    version = match[1]
    config = json.loads((root / ".github/native-release.json").read_text())
    if set(config) != {"version", "platforms"} or config["version"] != version:
        raise ValueError("release selector must match the module version")
    selected = config["platforms"]
    if not isinstance(selected, list) or not selected or not all(isinstance(p, str) and p in PLATFORMS for p in selected):
        raise ValueError("release platforms must be a nonempty list of supported platforms")
    if len(set(selected)) != len(selected):
        raise ValueError("duplicate release platforms")
    notes = Path("docs/releases") / (version + ".md")
    path = root / notes
    path.resolve().relative_to(root.resolve())
    if path.is_symlink() or not path.is_file() or not path.read_text().strip():
        raise ValueError("release notes must be a nonempty regular file")
    if event == "push":
        if ref != "v" + version:
            raise ValueError("tag must exactly match the module and selector version")
        platforms = selected
    elif event == "pull_request":
        # A release's platform choice must not suppress Linux validation of
        # subsequent feature PRs such as the independent X11 implementation.
        platforms = list(PLATFORMS)
    else:
        raise ValueError("unsupported release workflow event")
    assets = ["dsh-" + p for p in platforms]
    if "darwin-aarch64" in platforms:
        assets.append("Dsh-macos-arm64.zip")
    return {
        "version": version,
        "matrix": {"include": [{"os": PLATFORMS[p], "platform": p} for p in platforms]},
        "assets": assets,
        "notes": notes.as_posix(),
    }


def verify_assets(directory, expected):
    if {p.name for p in directory.iterdir()} != set(expected):
        raise ValueError("downloaded assets do not exactly match the release plan")
    for name in expected:
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ValueError("release asset must be a nonempty regular file: " + name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True, choices=("pull_request", "push"))
    parser.add_argument("--ref", required=True)
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--verify-assets", type=Path)
    args = parser.parse_args()
    try:
        plan = build_plan(ROOT, args.event, args.ref)
        if args.verify_assets:
            verify_assets(args.verify_assets, plan["assets"])
        if args.github_output:
            with args.github_output.open("a") as output:
                for key in ("matrix", "assets", "notes"):
                    value = plan[key] if key == "notes" else json.dumps(plan[key], separators=(",", ":"))
                    output.write(key + "=" + value + "\n")
        print(json.dumps(plan))
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, "release plan: " + str(error) + "\n")


if __name__ == "__main__":
    main()
