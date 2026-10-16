#!/usr/bin/env python3
"""Check app version mirrors and the independent Python runtime version."""

from __future__ import annotations

import argparse
import ast
from pathlib import Path
import re
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[2]
SEMVER = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")


def check_versions(root: Path, tag: str | None = None) -> list[str]:
    """Return inconsistencies without importing or executing package code."""
    errors: list[str] = []
    version = (root / "VERSION").read_text().strip()
    if not SEMVER.fullmatch(version):
        errors.append("VERSION must contain a numeric MAJOR.MINOR.PATCH version")
    if tag is not None and tag != f"v{version}":
        errors.append(f"Release tag {tag!r} does not match VERSION v{version}")
    if tag is not None:
        changelog = (root / "CHANGELOG.md").read_text()
        if not re.search(rf"^## \[{re.escape(version)}\] - [0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}}$", changelog, re.M):
            errors.append("Tagged releases require a dated CHANGELOG entry for VERSION")
    project = (root / "Sci-Station.xcodeproj/project.pbxproj").read_text()
    marketing = re.findall(r"MARKETING_VERSION\s*=\s*([^;]+);", project)
    if not marketing or any(value.strip(' \"') != version for value in marketing):
        errors.append("Every Xcode MARKETING_VERSION must mirror VERSION")
    builds = re.findall(r"CURRENT_PROJECT_VERSION\s*=\s*([^;]+);", project)
    if not builds or len(set(builds)) != 1 or not re.fullmatch(r"[1-9][0-9]*", builds[0].strip()):
        errors.append("Xcode build configurations must share a positive integer CURRENT_PROJECT_VERSION")
    for path, label in [("README.md", "当前版本"), ("docs/README.en.md", "Current version")]:
        text = (root / path).read_text()
        matches = re.findall(rf"^> {label}[:：]\s*(\S+)\s*$", text, re.M)
        if matches != [version]:
            errors.append(f"{path} version header must mirror VERSION")
    runtime = tomllib.loads((root / "AgentRuntime/pyproject.toml").read_text())["project"]["version"]
    tree = ast.parse((root / "AgentRuntime/sci_station_agent/__init__.py").read_text())
    mirrors = [node.value.value for node in tree.body if isinstance(node, ast.Assign)
               and any(isinstance(target, ast.Name) and target.id == "__version__" for target in node.targets)
               and isinstance(node.value, ast.Constant)]
    if not isinstance(runtime, str) or not SEMVER.fullmatch(runtime) or mirrors != [runtime]:
        errors.append("Python __version__ must mirror its independent pyproject.toml version")
    return errors


def main() -> int:
    """Validate repository versions and optionally a release tag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag")
    args = parser.parse_args()
    try:
        errors = check_versions(ROOT, args.tag)
    except (OSError, ValueError, KeyError, SyntaxError) as error:
        errors = [str(error)]
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if not errors:
        print("App version mirrors and independent runtime version passed.")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
