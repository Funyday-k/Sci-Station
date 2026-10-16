#!/usr/bin/env python3
"""Require a concrete requirement reference in pull request descriptions."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]


def has_reference(body: str, root: Path) -> bool:
    """Accept Issue references or existing versioned decision/backlog targets."""
    body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    body = re.sub(r"```.*?```", "", body, flags=re.S)
    issue_text = re.sub(r"`[^`]*`", "", body)
    if re.search(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)\s+#([1-9][0-9]*)\b", issue_text, re.I):
        return True
    if re.search(r"https://github\.com/[\w.-]+/[\w.-]+/issues/[1-9][0-9]*(?=[\s)#?]|$)", issue_text):
        return True
    pattern = r"(?<![\w/.-])(docs/(?:architecture/ADR-[0-9]{4}-[a-z0-9-]+\.md|rfcs/RFC-[0-9]{4}-[a-z0-9-]+\.md|BACKLOG\.md))(?:#([a-z0-9-]+))?"
    for match in re.finditer(pattern, body):
        path, anchor = match.groups()
        target = root / path
        if not target.is_file():
            continue
        if path.endswith("BACKLOG.md"):
            if not anchor:
                continue
            headings = re.findall(r"^## (.+)$", target.read_text(), re.M)
            anchors = [re.sub(r"[^\w -]", "", heading.lower()).replace(" ", "-") for heading in headings]
            if anchor not in anchors:
                continue
        return True
    return False


def main() -> int:
    """Read GitHub's JSON event file as data, never as executable shell text."""
    if os.environ.get("GITHUB_EVENT_NAME") != "pull_request":
        print("PR traceability applies on pull_request events.")
        return 0
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    body = event.get("pull_request", {}).get("body") or ""
    if has_reference(body, ROOT):
        print("PR requirement reference found; relevance remains part of review.")
        return 0
    print("error: Link an Issue (Closes #123 or Issue URL), existing RFC/ADR, or anchored docs/BACKLOG.md item.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
