from __future__ import annotations

import json
from pathlib import Path


def save_checkpoint(run_directory: Path, checkpoint: dict) -> None:
    run_directory.mkdir(parents=True, exist_ok=True)
    (run_directory / "checkpoint.json").write_text(json.dumps(checkpoint, sort_keys=True), encoding="utf-8")


def load_checkpoint(run_directory: Path) -> dict | None:
    path = run_directory / "checkpoint.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))
