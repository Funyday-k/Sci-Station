from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

JsonDict = dict[str, Any]

FIXTURE_SCHEMA_VERSION = 1


@dataclass(frozen=True)
class SidecarFixture:
    meta: JsonDict
    actions: list[JsonDict]


def load_fixture(path: Path | None) -> SidecarFixture | None:
    if path is None:
        return None
    lines = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not lines:
        raise ValueError(f"Fixture is empty: {path}")
    meta = lines[0]
    version = meta.get("fixture_schema_version")
    if version != FIXTURE_SCHEMA_VERSION:
        raise ValueError(f"Unsupported fixture schema version {version}; expected {FIXTURE_SCHEMA_VERSION}")
    actions = lines[1:]
    for index, action in enumerate(actions, start=2):
        kind = action.get("kind")
        if kind not in {"event", "wait_for_resume", "sleep", "crash"}:
            raise ValueError(f"Unsupported fixture action kind on line {index}: {kind}")
        if kind == "event":
            envelope = action.get("envelope")
            if not isinstance(envelope, dict):
                raise ValueError(f"Fixture event on line {index} must include envelope")
            if "event" not in envelope:
                raise ValueError(f"Fixture event on line {index} must include runtime event")
    return SidecarFixture(meta=meta, actions=actions)
