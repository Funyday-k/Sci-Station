"""Scenario orchestrator.

Wires together :class:`Scenario`, :class:`EventLogProbe` and
:class:`FileProbe` and walks through the steps with a pluggable
:class:`UIDriver`.

The runner is intentionally *driver-free* in the first slice -- callers may
pass a :class:`NullDriver` (the default) which records each step verbatim
without performing any UI action. P-AT.3 plugs in an Accessibility-API
driver, P-AT.4 plugs in XCUITest, both behind the same protocol so this
module never grows a hard dependency on a particular driver stack.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping, Sequence

from sci_station_agent.uitest.drivers.base import NullDriver, UIDriver
from sci_station_agent.uitest.events import EventLogProbe, EventQuery
from sci_station_agent.uitest.files import FileProbe
from sci_station_agent.uitest.scenario import (
    Assertion,
    Scenario,
    ScenarioValidationError,
    Step,
)


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class StepOutcome:
    step: Step
    succeeded: bool
    detail: str = ""


@dataclass(frozen=True)
class AssertionOutcome:
    assertion: Assertion
    succeeded: bool
    detail: str = ""


@dataclass(frozen=True)
class ScenarioRunResult:
    scenario_id: str
    research_root: Path
    steps: tuple[StepOutcome, ...]
    assertions: tuple[AssertionOutcome, ...]
    notes: tuple[str, ...] = field(default_factory=tuple)

    @property
    def succeeded(self) -> bool:
        return all(step.succeeded for step in self.steps) and all(
            outcome.succeeded for outcome in self.assertions
        )

    def to_summary(self) -> dict[str, Any]:
        return {
            "scenario_id": self.scenario_id,
            "research_root": str(self.research_root),
            "succeeded": self.succeeded,
            "step_count": len(self.steps),
            "step_failures": [
                {
                    "kind": outcome.step.kind,
                    "target": outcome.step.target,
                    "detail": outcome.detail,
                }
                for outcome in self.steps
                if not outcome.succeeded
            ],
            "assertion_failures": [
                {
                    "channel": outcome.assertion.channel,
                    "description": outcome.assertion.description,
                    "detail": outcome.detail,
                }
                for outcome in self.assertions
                if not outcome.succeeded
            ],
            "notes": list(self.notes),
        }


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------


class ScenarioRunner:
    """Run a :class:`Scenario` against a research root directory."""

    def __init__(
        self,
        research_root: str | Path,
        *,
        driver: UIDriver | None = None,
    ) -> None:
        self.research_root = Path(research_root).expanduser().resolve()
        self.driver: UIDriver = driver or NullDriver()
        self.event_probe = EventLogProbe(self.research_root)
        self.file_probe = FileProbe(self.research_root)

    # -- public API ----------------------------------------------------------

    def run(self, scenario: Scenario) -> ScenarioRunResult:
        notes: list[str] = []
        steps_outcomes = self._execute_steps(scenario, notes=notes)
        if any(not outcome.succeeded for outcome in steps_outcomes):
            notes.append(
                "scenario aborted before assertions because one or more steps failed"
            )
            return ScenarioRunResult(
                scenario_id=scenario.id,
                research_root=self.research_root,
                steps=tuple(steps_outcomes),
                assertions=tuple(),
                notes=tuple(notes),
            )

        assertion_outcomes = tuple(
            self._evaluate_assertion(assertion) for assertion in scenario.assertions
        )
        return ScenarioRunResult(
            scenario_id=scenario.id,
            research_root=self.research_root,
            steps=tuple(steps_outcomes),
            assertions=assertion_outcomes,
            notes=tuple(notes),
        )

    # -- step execution ------------------------------------------------------

    def _execute_steps(
        self, scenario: Scenario, *, notes: list[str]
    ) -> Sequence[StepOutcome]:
        outcomes: list[StepOutcome] = []
        for step in scenario.steps:
            try:
                detail = self._execute_step(step)
                outcomes.append(StepOutcome(step=step, succeeded=True, detail=detail))
            except StepError as exc:
                outcomes.append(
                    StepOutcome(step=step, succeeded=False, detail=str(exc))
                )
                break
            except Exception as exc:  # pragma: no cover - defensive
                notes.append(f"step '{step.kind}' raised unexpected error: {exc}")
                outcomes.append(
                    StepOutcome(step=step, succeeded=False, detail=str(exc))
                )
                break
        return outcomes

    def _execute_step(self, step: Step) -> str:
        kind = step.kind.lower()
        if kind == "click":
            self._require(step, "target")
            self.driver.click(step.target or "")
            return f"click({step.target})"
        if kind == "type":
            self._require(step, "target")
            value = step.value if step.value is not None else ""
            self.driver.type_text(step.target or "", str(value))
            return f"type({step.target}, {value!r})"
        if kind == "drag":
            self._require(step, "target")
            self._require(step, "to")
            self.driver.drag(step.target or "", step.to or "")
            return f"drag({step.target} -> {step.to})"
        if kind == "wait_for_event":
            if not step.event:
                raise StepError("'wait_for_event' requires 'event'")
            timeout = step.timeout_seconds or 10.0
            ev = self.event_probe.wait_for(
                EventQuery(event=step.event), timeout_seconds=timeout
            )
            if ev is None:
                raise StepError(
                    f"timed out after {timeout:.1f}s waiting for "
                    f"event '{step.event}'"
                )
            return f"wait_for_event({step.event}) -> matched"
        if kind == "sleep":
            seconds = step.seconds or 0.0
            if seconds > 0:
                import time

                time.sleep(seconds)
            return f"sleep({seconds:.3f}s)"
        if kind == "test_bridge":
            if not step.command:
                raise StepError("'test_bridge' requires 'command'")
            self.driver.send_test_bridge(step.command, dict(step.args))
            return f"test_bridge({step.command})"
        raise StepError(f"unknown step kind '{step.kind}'")

    # -- assertion evaluation ------------------------------------------------

    def _evaluate_assertion(self, assertion: Assertion) -> AssertionOutcome:
        try:
            if assertion.channel == "event":
                ok, detail = self._check_event_assertion(assertion.args)
            elif assertion.channel == "file":
                ok, detail = self._check_file_assertion(assertion.args)
            elif assertion.channel == "visual":
                ok, detail = (
                    False,
                    "visual channel is deferred to P-AT.4; no baseline diff yet",
                )
            else:  # pragma: no cover - validated earlier
                ok, detail = (False, f"unknown channel '{assertion.channel}'")
        except Exception as exc:  # pragma: no cover - defensive
            ok, detail = (False, f"assertion crashed: {exc}")

        if not assertion.expect_pass:
            ok = not ok
            detail = f"(expect_pass=false) {detail}".strip()

        return AssertionOutcome(assertion=assertion, succeeded=ok, detail=detail)

    def _check_event_assertion(self, args: Mapping[str, Any]) -> tuple[bool, str]:
        event = str(args.get("event") or "").strip()
        if not event:
            return False, "event assertion missing 'event' field"
        query = EventQuery(
            event=event,
            workspace_id=_optional_str(args, "workspace_id"),
            project_id=_optional_str(args, "project_id"),
            thread_id=_optional_str(args, "thread_id"),
            run_id=_optional_str(args, "run_id"),
            payload_contains=dict(args.get("payload_contains") or {}),
        )
        timeout = float(args.get("timeout_seconds") or 0.0)
        if timeout > 0:
            ev = self.event_probe.wait_for(query, timeout_seconds=timeout)
        else:
            matches = self.event_probe.filter(query)
            ev = matches[0] if matches else None

        min_count = int(args.get("min_count") or 1)
        if min_count > 1:
            count = len(self.event_probe.filter(query))
            if count < min_count:
                return (
                    False,
                    f"expected at least {min_count} matching event(s), found {count}",
                )
            return True, f"matched {count} event(s)"

        if ev is None:
            return (
                False,
                f"no event matched query event='{event}' "
                f"payload_contains={dict(query.payload_contains)}",
            )
        return True, f"matched event recordedAt={ev.recorded_at}"

    def _check_file_assertion(self, args: Mapping[str, Any]) -> tuple[bool, str]:
        relative_path = str(args.get("path") or "").strip()
        if not relative_path:
            return False, "file assertion missing 'path' field"
        loader = str(args.get("loader") or "json").lower()
        try:
            ok = self.file_probe.matches(
                relative_path,
                loader=loader,
                expected_subset=args.get("expected_subset"),
                expected_equals=args.get("expected_equals"),
                expected_contains_text=_optional_str(args, "expected_contains_text"),
            )
        except FileNotFoundError as exc:
            return False, f"file not found: {exc}"
        except Exception as exc:
            return False, f"file probe error: {exc}"
        return ok, ("matched" if ok else "did not match expected subset/equals")

    @staticmethod
    def _require(step: Step, field_name: str) -> None:
        if getattr(step, field_name, None) in (None, ""):
            raise StepError(
                f"step kind '{step.kind}' requires '{field_name}'"
            )


class StepError(RuntimeError):
    """Raised when a scenario step cannot be executed."""


def _optional_str(args: Mapping[str, Any], key: str) -> str | None:
    value = args.get(key)
    if value is None:
        return None
    return str(value)


__all__ = [
    "AssertionOutcome",
    "ScenarioRunResult",
    "ScenarioRunner",
    "StepError",
    "StepOutcome",
]


# Re-export ScenarioValidationError so callers using only the runner module
# don't need to reach into ``scenario`` for the exception type.
ScenarioValidationError = ScenarioValidationError  # noqa: PLW0127
