from pathlib import Path

import pytest

from sci_station_agent.transport.schemas import load_fixture


FIXTURES = Path(__file__).parent / "fixtures"


@pytest.mark.parametrize(
    "name",
    [
        "run_success_paper_reading.jsonl",
        "run_approval_then_resume.jsonl",
        "run_failed.jsonl",
        "sidecar_crash_after_approval.jsonl",
        "handshake_timeout.jsonl",
        "invalid_schema_version.jsonl",
    ],
)
def test_sidecar_fixtures_load(name: str) -> None:
    fixture = load_fixture(FIXTURES / name)
    assert fixture is not None
    assert fixture.meta["fixture_schema_version"] == 1


def test_fixture_actions_include_golden_runtime_events() -> None:
    fixture = load_fixture(FIXTURES / "run_success_paper_reading.jsonl")
    events = [action["envelope"] for action in fixture.actions if action.get("kind") == "event"]
    assert [event["event"]["type"] for event in events][0] == "run_started"
    assert any(event["event"]["type"] == "artifact_draft" for event in events)
    assert events[-1]["event"]["type"] == "final_response"
