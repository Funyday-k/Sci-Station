#!/usr/bin/env python3
"""Prevent the legacy integration runner from collapsing into a giant file."""

from __future__ import annotations

from collections import Counter
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]


def check_runner(root: Path) -> list[str]:
    """Validate domain organization, file budgets and unique registrations."""
    base = root / "Tools/SciStationCoreTestRunner"
    errors: list[str] = []
    required = [base / "SciStationCoreTestRunner.swift", base / "CoreVerificationSuite.swift"]
    for path in required:
        if not path.is_file():
            errors.append(f"Missing runner entry/support: {path.name}")
    suites = list((base / "Suites").glob("*.swift"))
    if not suites or not list((base / "Support").glob("*.swift")):
        errors.append("Runner requires domain Suites and shared Support files")
    for path in base.rglob("*.swift"):
        budget = 100 if path.name == "SciStationCoreTestRunner.swift" else 200 if path.name == "CoreVerificationSuite.swift" else 1600
        lines = len(path.read_text().splitlines())
        if lines > budget:
            errors.append(f"{path.relative_to(root)}: {lines} lines exceeds {budget}")
    all_text = "\n".join(path.read_text() for path in base.rglob("*.swift"))
    checks = re.findall(r'await runCheck\("(\w+)"\)', all_text)
    functions = set(re.findall(r"\bfunc (\w+)\(", all_text))
    if not checks:
        errors.append("Runner has no registered checks")
    for name, count in Counter(checks).items():
        if count != 1 or name not in functions:
            errors.append(f"Check {name} must be registered once and have an implementation")
    return errors


def main() -> int:
    """Report runner architecture violations."""
    errors = check_runner(ROOT)
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if not errors:
        print("Core runner domain organization and file budgets passed.")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
