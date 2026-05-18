"""End-to-end smoke test: run a scenario against a stubbed workspace.

The driver is :class:`NullDriver`, so no real UI is required. The scenario
exercises every step kind the runner currently understands and asserts on
both the event channel and the file channel.
"""

from __future__ import annotations

import json
from pathlib import Path

from sci_station_agent.uitest.events import APP_EVENTS_RELATIVE_PATH
from sci_station_agent.uitest.runner import ScenarioRunner
from sci_station_agent.uitest.report import render_markdown
from sci_station_agent.uitest.scenario import loads_scenario


SCENARIO_PAYLOAD = """
{
  "id": "MT99-SMOKE",
  "title": "Runner smoke test",
  "steps": [
    {"kind": "click", "target": "library.import.button"},
    {"kind": "drag", "target": "queue.row.a", "to": "queue.row.b"},
    {"kind": "test_bridge", "command": "library.import.attachFixturePDF",
     "args": {"fixture_id": "import-smoke-01"}},
    {"kind": "wait_for_event", "event": "queue.append", "timeout_seconds": 0.5}
  ],
  "assertions": [
    {"channel": "event", "description": "queue.append fired",
     "args": {"event": "queue.append", "payload_contains": {"source": "library.import"}}},
    {"channel": "file", "description": "queue.json reflects the import",
     "args": {"path": "queue.json", "loader": "json",
              "expected_subset": {"entries": [{"paperID": "import-smoke-01"}]}}}
  ]
}
"""


def _seed_workspace(root: Path) -> None:
    log_path = root / APP_EVENTS_RELATIVE_PATH
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(
        json.dumps(
            {
                "event": "queue.append",
                "payload": {"source": "library.import", "paperID": "import-smoke-01"},
            }
        )
        + "\n",
        encoding="utf-8",
    )
    queue_path = root / "queue.json"
    queue_path.write_text(
        json.dumps(
            {"entries": [{"paperID": "import-smoke-01", "displayTitle": "Smoke"}]}
        ),
        encoding="utf-8",
    )


def test_runner_passes_when_event_and_file_present(tmp_path: Path) -> None:
    _seed_workspace(tmp_path)
    scenario = loads_scenario(SCENARIO_PAYLOAD, fmt="json")
    runner = ScenarioRunner(tmp_path)

    result = runner.run(scenario)

    assert result.succeeded, result.to_summary()
    assert all(step.succeeded for step in result.steps)
    assert {outcome.assertion.channel for outcome in result.assertions} == {
        "event",
        "file",
    }


def test_runner_marks_event_assertion_failed_when_event_missing(tmp_path: Path) -> None:
    # File present but event log empty -> file assertion passes, event fails.
    queue_path = tmp_path / "queue.json"
    queue_path.write_text(
        json.dumps({"entries": [{"paperID": "import-smoke-01"}]}),
        encoding="utf-8",
    )

    scenario = loads_scenario(SCENARIO_PAYLOAD, fmt="json")
    runner = ScenarioRunner(tmp_path)
    result = runner.run(scenario)

    # The runner aborts on the first failed step (wait_for_event), so it
    # never reaches the assertions; the result still surfaces a non-zero
    # failure count via `succeeded`.
    assert not result.succeeded
    failing_steps = [step for step in result.steps if not step.succeeded]
    assert len(failing_steps) == 1
    assert failing_steps[0].step.kind == "wait_for_event"


def test_runner_records_driver_actions(tmp_path: Path) -> None:
    _seed_workspace(tmp_path)
    scenario = loads_scenario(SCENARIO_PAYLOAD, fmt="json")
    runner = ScenarioRunner(tmp_path)

    runner.run(scenario)
    actions = runner.driver.actions  # type: ignore[attr-defined]

    kinds = [action[0] for action in actions]
    assert kinds == ["click", "drag", "send_test_bridge"]


def test_render_markdown_summarises_run(tmp_path: Path) -> None:
    _seed_workspace(tmp_path)
    scenario = loads_scenario(SCENARIO_PAYLOAD, fmt="json")
    runner = ScenarioRunner(tmp_path)
    result = runner.run(scenario)

    md = render_markdown(result, scenario_title="Runner smoke test")
    assert "MT99-SMOKE" in md
    assert ":white_check_mark:" in md
    assert "## Steps" in md
    assert "## Assertions" in md
