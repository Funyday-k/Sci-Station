from __future__ import annotations

import json
from pathlib import Path


def append_event(run_directory: Path, envelope: dict) -> None:
    run_directory.mkdir(parents=True, exist_ok=True)
    with (run_directory / "events.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(envelope, sort_keys=True) + "\n")


def read_events(run_directory: Path) -> list[dict]:
    path = run_directory / "events.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
