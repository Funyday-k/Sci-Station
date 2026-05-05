from __future__ import annotations

import json
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


def append_event(run_directory: Path, envelope: dict) -> None:
    run_directory.mkdir(parents=True, exist_ok=True)
    with (run_directory / "events.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(envelope, sort_keys=True) + "\n")


def read_events(run_directory: Path) -> list[dict]:
    path = run_directory / "events.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_replay(run_directory: Path, *, include_debug_text: bool = False, prompt_response: dict | None = None) -> dict:
    run_directory.mkdir(parents=True, exist_ok=True)
    events = read_events(run_directory)
    replay = {
        "schema_version": 1,
        "events": events,
        "checkpoint": _read_json(run_directory / "checkpoint.json"),
        "debug": _redacted_debug(prompt_response or {}) if include_debug_text else None,
    }
    (run_directory / "replay.json").write_text(json.dumps(replay, sort_keys=True, indent=2), encoding="utf-8")
    return replay


def read_replay(run_directory: Path) -> dict:
    path = run_directory / "replay.json"
    if not path.exists():
        return write_replay(run_directory)
    return json.loads(path.read_text(encoding="utf-8"))


def write_debug_bundle(run_directory: Path) -> Path:
    run_directory.mkdir(parents=True, exist_ok=True)
    allowed_names = ["events.jsonl", "checkpoint.json", "replay.json", "critic_report.json", "retrieval_trace.json"]
    manifest = {
        "schema_version": 1,
        "included_files": [name for name in allowed_names if (run_directory / name).exists()],
        "excluded_patterns": ["*.env", "*key*", "*token*", "private paths", "Keychain"],
        "privacy_notice": "Debug bundle excludes API keys, private path inventories, environment files, and Keychain content.",
    }
    (run_directory / "debug_bundle_manifest.json").write_text(json.dumps(manifest, sort_keys=True, indent=2), encoding="utf-8")
    bundle_path = run_directory / "debug_bundle.zip"
    with ZipFile(bundle_path, "w", ZIP_DEFLATED) as archive:
        archive.write(run_directory / "debug_bundle_manifest.json", "debug_bundle_manifest.json")
        for name in manifest["included_files"]:
            archive.write(run_directory / name, name)
    return bundle_path


def _read_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def _redacted_debug(value: dict) -> dict:
    redacted: dict = {}
    for key, item in value.items():
        lowered = key.lower()
        if any(secret in lowered for secret in ("api_key", "apikey", "token", "password", "secret")):
            redacted[key] = "[REDACTED]"
        elif isinstance(item, dict):
            redacted[key] = _redacted_debug(item)
        elif isinstance(item, str):
            without_home = item.replace(str(Path.home()), "~")
            redacted[key] = re.sub(r"(?<![\w:])/(?:[^\s]+/)*[^\s]+", "[PATH]", without_home)
        else:
            redacted[key] = item
    return redacted
