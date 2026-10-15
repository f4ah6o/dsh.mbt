#!/usr/bin/env python3
"""Check the resolved product graph and a fresh consumer of its source archive."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def run(args, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise SystemExit("Command failed in " + str(cwd) + ": " + " ".join(args) +
                         "\n" + result.stdout + result.stderr)
    return result.stdout


def check_graph(directory):
    graph = json.loads(run(["moon", "tree", "--json"], directory))
    if graph.get("status") != "success":
        raise SystemExit("Could not resolve the product dependency graph")
    names = {module["name"] for module in graph["modules"]}
    if "f4ah6o/hotpath" in names or "f4ah6o/dsh_perf" in names:
        raise SystemExit("Development performance dependencies entered the product graph")
    return sorted(names)


modules = check_graph(ROOT)
run(["moon", "package", "--frozen"])
version = re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "moon.mod").read_text(), re.M)
if version is None:
    raise SystemExit("Missing product version")
archive = ROOT / "_build/publish" / ("f4ah6o-dsh-" + version[1] + ".zip")
with zipfile.ZipFile(archive) as source:
    names = source.namelist()
    forbidden = [name for name in names if name.startswith(("tools/perf/", "vendor/hotpath/"))]
    if forbidden:
        raise SystemExit("Development-only files entered the product archive: " + repr(forbidden))
    if "benchmarks/engine_core/engine_bench.mbt" not in names:
        raise SystemExit("The existing engine benchmark was lost")
    with tempfile.TemporaryDirectory(prefix="dsh-performance-boundary-") as temporary:
        consumer = Path(temporary)
        source.extractall(consumer)
        run(["moon", "install"], consumer)
        consumer_modules = check_graph(consumer)
        if consumer_modules != modules:
            raise SystemExit("Source archive dependency graph differs from the checkout")
        run(["moon", "check", "api", "--target", "all", "--frozen", "--deny-warn"], consumer)

print(json.dumps({"product_modules": modules, "archive_files": len(names),
                  "optional_performance_source_excluded": True,
                  "fresh_archive_consumer_api_all_targets": "passed"}, indent=2))
