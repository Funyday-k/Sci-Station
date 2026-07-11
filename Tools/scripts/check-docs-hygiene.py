#!/usr/bin/env python3
"""Check version-controlled Sci-Station Markdown documentation hygiene."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[2]

DOC_ROOTS = [
    ROOT / "README.md",
    ROOT / "CHANGELOG.md",
    ROOT / "docs",
]

IGNORED_DOC_ROOTS = {
    ROOT / "docs" / "development",
    ROOT / "docs" / "user-feedback",
}

PUBLIC_DOCS = {
    "README.md",
    "docs/README.en.md",
    "docs/README.zh-CN.md",
    "docs/TUTORIAL.md",
    "docs/TUTORIAL.zh-CN.md",
    "docs/DEVELOPER.md",
}

@dataclass(frozen=True)
class Finding:
    severity: str
    rule: str
    path: str
    line: int
    text: str


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def markdown_files() -> list[Path]:
    files: list[Path] = []
    for root in DOC_ROOTS:
        if root.is_file():
            files.append(root)
        elif root.is_dir():
            files.extend(
                path
                for path in sorted(root.rglob("*.md"))
                if not any(path.is_relative_to(ignored) for ignored in IGNORED_DOC_ROOTS)
            )
    return sorted(set(files))


def scan_lines(files: list[Path]) -> list[Finding]:
    findings: list[Finding] = []
    public_patterns = [
        (
            "public-local-feedback",
            re.compile(r"(?:docs/)?user-feedback/|docs/user-feedback"),
            "Public docs should not expose the local feedback inbox.",
        ),
        (
            "public-internal-phase",
            re.compile(r"\bP\d{2}(?:\.\d+)?\b"),
            "Public docs should not expose internal phase labels.",
        ),
        (
            "public-placeholder",
            re.compile(r"\bTODO\b|(?i:\b(?:stub|placeholder|not implemented)\b)|待实现|未实现"),
            "Public docs should not expose implementation placeholders.",
        ),
        (
            "public-retired-terms",
            re.compile(r"\bQueue\b|ReadingPlan|Reading Plan|reading plan", re.I),
            "Public docs should not use retired product terms.",
        ),
        (
            "public-stale-version",
            re.compile(r"Beta 0\.1\.0"),
            "Public docs should not advertise stale beta versions.",
        ),
    ]
    for path in files:
        relative = rel(path)
        text = path.read_text(encoding="utf-8")
        for index, line in enumerate(text.splitlines(), start=1):
            if relative in PUBLIC_DOCS:
                for rule, pattern, _description in public_patterns:
                    if pattern.search(line):
                        findings.append(Finding("ERROR", rule, relative, index, line.strip()))
    return findings


def strip_fragment_and_query(target: str) -> str:
    target = target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1].strip()
    for marker in ("#", "?"):
        if marker in target:
            target = target.split(marker, 1)[0]
    return unquote(target)


def scan_links(files: list[Path]) -> list[Finding]:
    findings: list[Finding] = []
    link_pattern = re.compile(r"!?\[[^\]]+\]\(([^)]+)\)")
    external_prefixes = (
        "http://",
        "https://",
        "mailto:",
        "plugin://",
        "app://",
        "file://",
    )

    for path in files:
        relative = rel(path)
        for index, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            for match in link_pattern.finditer(line):
                raw_target = match.group(1).strip()
                if not raw_target or raw_target.startswith("#"):
                    continue
                if raw_target.startswith(external_prefixes):
                    continue
                target = strip_fragment_and_query(raw_target)
                if not target:
                    continue
                resolved = (path.parent / target).resolve()
                try:
                    resolved.relative_to(ROOT)
                except ValueError:
                    findings.append(
                        Finding(
                            "ERROR",
                            "local-link-outside-repo",
                            relative,
                            index,
                            raw_target,
                        )
                    )
                    continue
                if not resolved.exists():
                    findings.append(
                        Finding(
                            "ERROR",
                            "local-link-missing",
                            relative,
                            index,
                            raw_target,
                        )
                    )
    return findings


def print_findings(findings: list[Finding]) -> None:
    for finding in findings:
        print(
            f"{finding.severity} {finding.rule}: "
            f"{finding.path}:{finding.line}: {finding.text}"
        )


def main() -> int:
    files = markdown_files()
    findings = scan_lines(files) + scan_links(files)
    findings.sort(key=lambda item: (item.severity != "ERROR", item.path, item.line, item.rule))
    print_findings(findings)

    error_count = sum(1 for finding in findings if finding.severity == "ERROR")
    warning_count = sum(1 for finding in findings if finding.severity == "WARN")
    print(f"Checked {len(files)} Markdown files: {error_count} errors, {warning_count} warnings.")
    return 1 if error_count else 0


if __name__ == "__main__":
    sys.exit(main())
