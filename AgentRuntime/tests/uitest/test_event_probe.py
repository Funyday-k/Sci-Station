"""Exercise the EventLogProbe against synthetic ``app_events.jsonl`` files."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from sci_station_agent.uitest.events import (
    APP_EVENTS_RELATIVE_PATH,
    DebugEvent,
    EventLogProbe,
    EventQuery,
)


def _seed_log(root: Path, events: list[dict]) -> Path:
    log_dir = root / Path(APP_EVENTS_RELATIVE_PATH).parent
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = root / APP_EVENTS_RELATIVE_PATH
    log_path.write_text(
        "\n".join(json.dumps(payload) for payload in events) + "\n",
        encoding="utf-8",
    )
    return log_path


@pytest.fixture()
def workspace(tmp_path: Path) -> Path:
    return tmp_path


def test_read_all_returns_parsed_events(workspace: Path) -> None:
    _seed_log(
        workspace,
        [
            {"event": "queue.append", "payload": {"source": "library.import"}},
            {"event": "queue.reorder", "payload": {"from": 1, "to": 2}},
        ],
    )

    probe = EventLogProbe(workspace)
    events = probe.read_all()
    assert [ev.event for ev in events] == ["queue.append", "queue.reorder"]
    assert events[0].payload["source"] == "library.import"


def test_filter_combines_all_query_fields(workspace: Path) -> None:
    _seed_log(
        workspace,
        [
            {
                "event": "queue.append",
                "workspaceID": "w1",
                "projectID": "p1",
                "payload": {"source": "library.import"},
            },
            {
                "event": "queue.append",
                "workspaceID": "w1",
                "projectID": "p2",
                "payload": {"source": "manual.add"},
            },
        ],
    )

    probe = EventLogProbe(workspace)
    matches = probe.filter(
        EventQuery(
            event="queue.append",
            project_id="p1",
            payload_contains={"source": "library.import"},
        )
    )
    assert len(matches) == 1
    assert matches[0].workspace_id == "w1"


def test_filter_returns_empty_when_log_missing(tmp_path: Path) -> None:
    probe = EventLogProbe(tmp_path)
    assert probe.read_all() == []
    assert probe.filter(EventQuery(event="queue.append")) == []


def test_skips_malformed_lines(workspace: Path) -> None:
    log_path = workspace / APP_EVENTS_RELATIVE_PATH
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(
        '{"event":"queue.append"}\n'
        "this is not json\n"
        '{"event":"queue.reorder"}\n',
        encoding="utf-8",
    )

    probe = EventLogProbe(workspace)
    events = probe.read_all()
    assert [ev.event for ev in events] == ["queue.append", "queue.reorder"]


def test_wait_for_returns_none_when_event_never_arrives(workspace: Path) -> None:
    probe = EventLogProbe(workspace)
    matched = probe.wait_for(
        EventQuery(event="queue.append"),
        timeout_seconds=0.05,
        poll_interval=0.01,
    )
    assert matched is None


def test_wait_for_finds_already_persisted_event(workspace: Path) -> None:
    _seed_log(workspace, [{"event": "queue.append"}])
    probe = EventLogProbe(workspace)
    matched = probe.wait_for(
        EventQuery(event="queue.append"),
        timeout_seconds=0.05,
        poll_interval=0.01,
    )
    assert isinstance(matched, DebugEvent)
    assert matched.event == "queue.append"
