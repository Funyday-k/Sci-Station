"""Validate Scenario / Step / Assertion parsing against canonical fixtures."""

from __future__ import annotations

from pathlib import Path

import pytest

from sci_station_agent.uitest.scenario import (
    ScenarioValidationError,
    load_scenario,
    loads_scenario,
)


SCENARIO_DIR = (
    Path(__file__).resolve().parents[2]
    / "sci_station_agent"
    / "uitest"
    / "scenarios"
)


def test_loads_canonical_json_scenario_round_trip() -> None:
    scenario = load_scenario(SCENARIO_DIR / "MT02-01_import_pdf.json")
    assert scenario.id == "MT02-01"
    assert "library" in scenario.tags
    assert len(scenario.steps) == 2
    assert scenario.steps[0].kind == "click"
    assert scenario.steps[0].target == "sidebar.tab.library"
    channels = {assertion.channel for assertion in scenario.assertions}
    assert {"file"}.issubset(channels)


def test_loads_yaml_scenario_when_pyyaml_present() -> None:
    pytest.importorskip("yaml")
    scenario = load_scenario(SCENARIO_DIR / "MT02-01_import_pdf.yaml")
    assert scenario.id == "MT02-01"
    assert scenario.steps[-1].kind == "test_bridge"
    assert scenario.steps[-1].command == "library.import.attachFixturePDF"


def test_smoke_yaml_scenario_library_loads_and_covers_drag() -> None:
    pytest.importorskip("yaml")
    scenario_paths = sorted(SCENARIO_DIR.glob("*.yaml"))
    scenarios = [load_scenario(path) for path in scenario_paths]

    assert len(scenarios) >= 4
    ids = [scenario.id for scenario in scenarios]
    assert len(ids) == len(set(ids))
    assert {"MT02-01", "MT18-P43.9-03", "MT03-01", "MT07-03"}.issubset(ids)
    assert any(step.kind == "drag" for scenario in scenarios for step in scenario.steps)
    supported_steps = {"click", "type", "drag", "wait_for_event", "sleep", "test_bridge"}
    assert {
        step.kind for scenario in scenarios for step in scenario.steps
    }.issubset(supported_steps)


def test_rejects_scenario_without_steps() -> None:
    payload = """
    {
      "id": "MT99-99",
      "title": "Empty",
      "steps": [],
      "assertions": [
        {"channel": "event", "description": "stub", "args": {"event": "x"}}
      ]
    }
    """
    with pytest.raises(ScenarioValidationError):
        loads_scenario(payload, fmt="json")


def test_rejects_unknown_assertion_channel() -> None:
    payload = """
    {
      "id": "MT99-99",
      "title": "Bad channel",
      "steps": [{"kind": "sleep", "seconds": 0}],
      "assertions": [{"channel": "telemetry", "description": "?"}]
    }
    """
    with pytest.raises(ScenarioValidationError):
        loads_scenario(payload, fmt="json")


def test_rejects_step_without_kind() -> None:
    payload = """
    {
      "id": "MT99-99",
      "title": "Bad step",
      "steps": [{"target": "library.list"}],
      "assertions": [
        {"channel": "event", "description": "x", "args": {"event": "x"}}
      ]
    }
    """
    with pytest.raises(ScenarioValidationError):
        loads_scenario(payload, fmt="json")
