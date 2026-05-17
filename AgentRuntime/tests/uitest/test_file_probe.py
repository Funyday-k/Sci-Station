"""Exercise FileProbe loaders + subset matcher."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from sci_station_agent.uitest.files import FileProbe, _subset_match


def test_load_json_round_trips(tmp_path: Path) -> None:
    target = tmp_path / "queue.json"
    payload = {"entries": [{"paperID": "p1"}, {"paperID": "p2"}]}
    target.write_text(json.dumps(payload), encoding="utf-8")

    probe = FileProbe(tmp_path)
    loaded = probe.load_json("queue.json")
    assert loaded.content == payload


def test_load_jsonl_returns_list(tmp_path: Path) -> None:
    target = tmp_path / "events.jsonl"
    target.write_text('{"a":1}\n{"a":2}\n\n', encoding="utf-8")

    probe = FileProbe(tmp_path)
    loaded = probe.load_jsonl("events.jsonl")
    assert loaded.content == [{"a": 1}, {"a": 2}]


def test_load_yaml_when_pyyaml_present(tmp_path: Path) -> None:
    pytest.importorskip("yaml")
    target = tmp_path / "queue.yaml"
    target.write_text(
        "entries:\n  - paperID: p1\n  - paperID: p2\n",
        encoding="utf-8",
    )

    probe = FileProbe(tmp_path)
    loaded = probe.load_yaml("queue.yaml")
    assert loaded.content == {"entries": [{"paperID": "p1"}, {"paperID": "p2"}]}


def test_path_traversal_is_rejected(tmp_path: Path) -> None:
    probe = FileProbe(tmp_path)
    with pytest.raises(ValueError):
        probe.resolve("../escape")


def test_subset_match_supports_nested_lists() -> None:
    actual = {
        "entries": [
            {"paperID": "p1", "tags": ["a", "b"]},
            {"paperID": "p2", "tags": ["c"]},
        ]
    }
    expected = {"entries": [{"paperID": "p2"}, {"paperID": "p1", "tags": ["b"]}]}
    assert _subset_match(actual, expected)


def test_subset_match_rejects_missing_key() -> None:
    actual = {"entries": [{"paperID": "p1"}]}
    expected = {"entries": [{"paperID": "p2"}]}
    assert not _subset_match(actual, expected)


def test_matches_uses_loader_to_compare_subset(tmp_path: Path) -> None:
    target = tmp_path / "queue.json"
    target.write_text(
        json.dumps({"entries": [{"paperID": "p1"}, {"paperID": "p2"}]}),
        encoding="utf-8",
    )

    probe = FileProbe(tmp_path)
    assert probe.matches(
        "queue.json",
        loader="json",
        expected_subset={"entries": [{"paperID": "p2"}]},
    )
    assert not probe.matches(
        "queue.json",
        loader="json",
        expected_subset={"entries": [{"paperID": "missing"}]},
    )
