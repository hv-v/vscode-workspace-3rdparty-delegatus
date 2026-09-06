#!/usr/bin/env python3
"""Driver for {{PROJECT}} - exercises the running process from outside.

Subcommands: probe | watch --seconds N | smoke   (add project-specific ones)

Rules for filling this in:
  - Subscribe/connect BEFORE triggering, or you miss output already emitted.
  - Use explicit deadline loops, never a bare sleep.
  - On timeout, print what WAS observed - "no data" is not a diagnosis.
  - Talk to the interfaces directly; avoid CLIs that need their own daemon.
  - `smoke` must exit non-zero on any failed check.
"""

import argparse
import json
import sys

OUT = "/out/report.json"


def probe() -> dict:
    """Ground truth: what is actually reachable. No assertions."""
    raise NotImplementedError


def watch(seconds: int) -> dict:
    """Capture the output channels for `seconds` and return what arrived."""
    raise NotImplementedError


def smoke() -> int:
    """Run every check in dependency order and print a verdict block."""
    checks: dict[str, bool] = {}
    # checks["{{name}}"] = ...

    with open(OUT, "w") as fh:
        json.dump(checks, fh, indent=2)

    print("=== VERDICT ===")
    for name, ok in checks.items():
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    return 0 if checks and all(checks.values()) else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("probe")
    sub.add_parser("smoke")
    w = sub.add_parser("watch")
    w.add_argument("--seconds", type=int, default=5)

    args = ap.parse_args()
    if args.cmd == "smoke":
        return smoke()
    print(json.dumps(probe() if args.cmd == "probe" else watch(args.seconds), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
