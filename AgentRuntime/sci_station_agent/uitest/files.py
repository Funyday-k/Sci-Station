"""Probe channel #2: read workspace-local files (yaml / jsonl / md).

The orchestrator's file probe never writes; it reads the same on-disk state
the App produced. Callers express expectations as either:

* exact-match against a YAML/JSON tree, or
* a "contains" subset match (the file's tree must include every key/value
  in the expected mapping at the matching path).

YAML loading is lazy-imported; JSON is supported natively. JSONL files are
parsed line-by-line and exposed as a list of records. SwiftUI runtime
warnings are exposed via :func:`parse_swiftui_warnings_log`.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

import json


# Mirrors `Sci-Station/Testing/SwiftUIRuntimeWarningCapture.swift::relativePath`.
SWIFTUI_WARNINGS_RELATIVE_PATH = ".sci-station/debug/swiftui_warnings.log"


@dataclass(frozen=True)
class SwiftUIWarning:
    """One captured SwiftUI runtime warning."""

    timestamp: str
    subsystem: str
    category: str
    process: str
    message: str

    @staticmethod
    def parse(line: str) -> "SwiftUIWarning | None":
        # Format is tab-separated: timestamp\tsubsystem\tcategory\tprocess\tmessage.
        fields = line.rstrip("\n").split("\t", maxsplit=4)
        if len(fields) != 5:
            return None
        return SwiftUIWarning(
            timestamp=fields[0],
            subsystem=fields[1],
            category=fields[2],
            process=fields[3],
            message=fields[4],
        )


def parse_swiftui_warnings_log(path: Path) -> list[SwiftUIWarning]:
    """Parse ``swiftui_warnings.log`` produced by ``SwiftUIRuntimeWarningCapture``.

    Returns an empty list when the file is missing — the App only creates
    the file in DEBUG builds with an open workspace, so a missing file is
    a soft absence rather than an error. Malformed lines are skipped.
    """

    if not path.exists():
        return []
    warnings: list[SwiftUIWarning] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        parsed = SwiftUIWarning.parse(line)
        if parsed is not None:
            warnings.append(parsed)
    return warnings


@dataclass(frozen=True)
class PersistedFile:
    """A loaded workspace artifact."""

    path: Path
    content: Any

    @property
    def exists(self) -> bool:  # pragma: no cover - trivially True at construction
        return True


class FileProbe:
    """Read workspace-local YAML / JSON / JSONL files."""

    def __init__(self, research_root: str | Path) -> None:
        self.research_root = Path(research_root).expanduser().resolve()

    # -- path resolution -----------------------------------------------------

    def resolve(self, relative_path: str | Path) -> Path:
        target = (self.research_root / relative_path).resolve()
        if not _is_within(target, self.research_root):
            raise ValueError(
                f"path '{relative_path}' escapes research root "
                f"'{self.research_root}'"
            )
        return target

    def exists(self, relative_path: str | Path) -> bool:
        return self.resolve(relative_path).exists()

    # -- loaders -------------------------------------------------------------

    def load_json(self, relative_path: str | Path) -> PersistedFile:
        path = self.resolve(relative_path)
        return PersistedFile(
            path=path, content=json.loads(path.read_text(encoding="utf-8"))
        )

    def load_yaml(self, relative_path: str | Path) -> PersistedFile:
        try:
            import yaml  # type: ignore[import-not-found]
        except ImportError as exc:  # pragma: no cover
            raise RuntimeError(
                "PyYAML is required to read YAML files; "
                "install via `pip install pyyaml`."
            ) from exc
        path = self.resolve(relative_path)
        return PersistedFile(
            path=path,
            content=yaml.safe_load(path.read_text(encoding="utf-8")),
        )

    def load_jsonl(self, relative_path: str | Path) -> PersistedFile:
        path = self.resolve(relative_path)
        records: list[Mapping[str, Any]] = []
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            records.append(json.loads(line))
        return PersistedFile(path=path, content=records)

    def load_text(self, relative_path: str | Path) -> PersistedFile:
        path = self.resolve(relative_path)
        return PersistedFile(path=path, content=path.read_text(encoding="utf-8"))

    # -- assertions ----------------------------------------------------------

    def matches(
        self,
        relative_path: str | Path,
        *,
        loader: str,
        expected_subset: Any | None = None,
        expected_equals: Any | None = None,
        expected_contains_text: str | None = None,
    ) -> bool:
        """Generic matcher used by scenario assertions.

        ``loader`` selects how to read the file: ``"json"``, ``"yaml"``,
        ``"jsonl"`` or ``"text"``. Exactly one of ``expected_subset`` /
        ``expected_equals`` / ``expected_contains_text`` should be provided.
        """

        loader = loader.lower()
        if loader == "json":
            file = self.load_json(relative_path)
        elif loader == "yaml":
            file = self.load_yaml(relative_path)
        elif loader == "jsonl":
            file = self.load_jsonl(relative_path)
        elif loader == "text":
            file = self.load_text(relative_path)
        else:
            raise ValueError(f"unknown file loader '{loader}'")

        if expected_equals is not None:
            return file.content == expected_equals
        if expected_subset is not None:
            return _subset_match(file.content, expected_subset)
        if expected_contains_text is not None:
            return expected_contains_text in str(file.content)
        return True


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _subset_match(actual: Any, expected: Any) -> bool:
    """Recursive subset match.

    * For mappings: every key in ``expected`` must be present in ``actual``
      with a value that subset-matches.
    * For sequences: every element in ``expected`` must subset-match
      *some* element in ``actual`` (order-agnostic, supports duplicates).
    * For scalars: direct equality.
    """

    if isinstance(expected, Mapping):
        if not isinstance(actual, Mapping):
            return False
        for key, value in expected.items():
            if key not in actual:
                return False
            if not _subset_match(actual[key], value):
                return False
        return True

    if isinstance(expected, (list, tuple)):
        if not isinstance(actual, (list, tuple)):
            return False
        remaining = list(actual)
        for needle in expected:
            for index, candidate in enumerate(remaining):
                if _subset_match(candidate, needle):
                    remaining.pop(index)
                    break
            else:
                return False
        return True

    return actual == expected


def _is_within(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False
