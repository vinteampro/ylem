#!/usr/bin/env python3
"""Run the same bounded, fail-closed Godot checks locally and in CI (stdlib only)."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent
ERROR = re.compile(r"(?:SCRIPT ERROR:|ERROR:|FAIL:|ObjectDB instances (?:were )?leaked|resources still in use)")
CASES = (
    ("import", ["--editor", "--import"], "", 180),
    ("physics", ["--script", "res://tools/sim_check.gd"], "ИТОГ: всё в допусках", 180),
    ("model", ["--script", "res://tools/model_contract_check.gd"], "MODEL CONTRACTS:", 180),
    ("consistency", ["--script", "res://tools/consistency_check.gd"], "CONSISTENCY:", 180),
    ("lifecycle", ["--script", "res://tools/lifecycle_check.gd", "--", "--no-music", "--no-results"], "LIFECYCLE:", 90),
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--logs", type=Path, default=ROOT / "build" / "checks")
    args = parser.parse_args()
    executable = shutil.which(args.godot)
    if not executable:
        parser.error(f"Godot not found: {args.godot}")
    version = subprocess.run([executable, "--version"], capture_output=True, text=True, timeout=15, check=True).stdout.strip()
    if not version.startswith("4.7.2.stable"):
        parser.error(f"Use the release engine, Godot 4.7.2 stable; found {version}")
    args.logs.mkdir(parents=True, exist_ok=True)
    print(f"Godot {version}; {sys.platform}; logs: {args.logs}", flush=True)
    failed = []
    for name, flags, marker, timeout in CASES:
        start = time.monotonic()
        command = [executable, "--headless", "--path", str(ROOT), *flags]
        log = args.logs / f"{name}.log"
        try:
            with log.open("w", encoding="utf-8") as stream:
                result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
            output = log.read_text(encoding="utf-8", errors="replace")
            ok = result.returncode == 0 and not ERROR.search(output) and marker in output
            # Check summaries as well as process status: Godot can return zero
            # after a script error or an early return from a test entry point.
            if marker.endswith(":"):
                ok = ok and bool(re.search(re.escape(marker) + r" \d+ checks, 0 failures", output))
        except subprocess.TimeoutExpired:
            ok = False
            with log.open("a", encoding="utf-8") as stream:
                stream.write(f"\nFAIL: timeout after {timeout} seconds\n")
        print(f"{'PASS' if ok else 'FAIL'} {name} ({time.monotonic() - start:.1f}s)", flush=True)
        if not ok:
            failed.append(name)
            print(log.read_text(encoding="utf-8", errors="replace")[-6000:], flush=True)
        if name == "import" and not ok:
            break
    print("CHECKS PASSED" if not failed else "CHECKS FAILED: " + ", ".join(failed), flush=True)
    return bool(failed)


if __name__ == "__main__":
    raise SystemExit(main())
