#!/usr/bin/env python3
"""Isolated launcher for the Sci-Station sidecar bundled in the macOS app."""

from __future__ import annotations

import runpy
import sys
from pathlib import Path


def main() -> int:
    runtime_root = Path(__file__).resolve().parent
    package_root = runtime_root / "sci_station_agent"
    if not package_root.is_dir():
        raise RuntimeError(f"Bundled sidecar package is missing: {package_root}")

    # Python is launched with -I, so user site packages, PYTHONPATH, and the
    # current working directory cannot replace the sealed app-bundle package.
    sys.path.insert(0, str(runtime_root))
    runpy.run_module("sci_station_agent.main", run_name="__main__")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
