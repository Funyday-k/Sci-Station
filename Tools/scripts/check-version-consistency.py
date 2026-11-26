#!/usr/bin/env python3
"""Check the desktop version, build number, and release tag."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
SEMVER = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")


def check_versions(root: Path, tag: str | None = None) -> list[str]:
    """Return inconsistencies without importing or executing package code."""
    errors: list[str] = []
    version = (root / "VERSION").read_text().removesuffix("\n")
    if not SEMVER.fullmatch(version):
        errors.append("VERSION must contain a numeric MAJOR.MINOR.PATCH version")
    if tag is not None and tag != f"v{version}":
        errors.append(f"Release tag {tag!r} does not match VERSION v{version}")
    if tag is not None:
        changelog = (root / "CHANGELOG.md").read_text()
        if not re.search(rf"^## \[{re.escape(version)}\] - [0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}}$", changelog, re.M):
            errors.append("Tagged releases require a dated CHANGELOG entry for VERSION")
    build_number = (root / "BUILD_NUMBER").read_text().removesuffix("\n")
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        errors.append("BUILD_NUMBER must contain a positive decimal integer")
    for path, label in [("README.md", "当前版本"), ("docs/README.en.md", "Current version")]:
        text = (root / path).read_text()
        matches = re.findall(rf"^> {label}[:：]\s*(\S+)\s*$", text, re.M)
        if matches != [version]:
            errors.append(f"{path} version header must mirror VERSION")
    return errors


def main() -> int:
    """Validate repository versions and optionally a release tag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag")
    args = parser.parse_args()
    try:
        errors = check_versions(ROOT, args.tag)
    except (OSError, ValueError) as error:
        errors = [str(error)]
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if not errors:
        print("Desktop version and build number checks passed.")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
