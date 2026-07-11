"""Scenario data model + loader for the AI Usage Test orchestrator.

A scenario is a deterministic recipe for one MT (manual test) case. It binds:

* ``id`` -- the public manual-test identifier (e.g. ``MT02-01``).
* ``setup`` -- preflight workspace state (research-root path, fixtures).
* ``steps`` -- ordered actions for the driver to perform via accessibility
  identifiers / Test Bridge commands.
* ``assertions`` -- post-conditions checked across **three independent**
  channels:

      1. ``event``  -- expected entries in ``app_events.jsonl``
      2. ``file``   -- expected workspace-local files / yaml fragments
      3. ``visual`` -- screenshot baseline diff (deferred)

The loader supports JSON natively and YAML when PyYAML is installed.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping, Sequence

import json

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Step:
    """A single driver action.

    ``kind`` selects the driver verb. The MVP supports::

        - "click"           target: <accessibility identifier>
        - "type"            target: <accessibility identifier>, value: str
        - "drag"            target: <accessibility identifier>, to: <axid>
        - "wait_for_event"  event: str, timeout_seconds: float
        - "sleep"           seconds: float
        - "test_bridge"     command: str, args: dict

    Unknown kinds raise during validation; new kinds must be added in the
    runner alongside their handler.
    """

    kind: str
    target: str | None = None
    value: Any | None = None
    to: str | None = None
    event: str | None = None
    seconds: float | None = None
    timeout_seconds: float | None = None
    command: str | None = None
    args: Mapping[str, Any] = field(default_factory=dict)
    description: str | None = None

    @staticmethod
    def from_mapping(raw: Mapping[str, Any]) -> "Step":
        kind = str(raw.get("kind") or "").strip()
        if not kind:
            raise ScenarioValidationError(
                "step is missing required 'kind' field"
            )
        return Step(
            kind=kind,
            target=_optional_str(raw, "target"),
            value=raw.get("value"),
            to=_optional_str(raw, "to"),
            event=_optional_str(raw, "event"),
            seconds=_optional_float(raw, "seconds"),
            timeout_seconds=_optional_float(raw, "timeout_seconds"),
            command=_optional_str(raw, "command"),
            args=dict(raw.get("args") or {}),
            description=_optional_str(raw, "description"),
        )


@dataclass(frozen=True)
class Assertion:
    """A post-condition checked after the driver finishes the steps.

    ``channel`` selects the probe::

        - "event"  -- pass kwargs to :class:`EventQuery`
        - "file"   -- pass kwargs to :class:`FileProbe.matches`
        - "visual" -- deferred until visual baseline support is available

    ``description`` is surfaced verbatim in the markdown report so a human
    can read pass/fail reasons without cross-referencing scenarios.
    """

    channel: str
    description: str
    args: Mapping[str, Any] = field(default_factory=dict)
    expect_pass: bool = True

    @staticmethod
    def from_mapping(raw: Mapping[str, Any]) -> "Assertion":
        channel = str(raw.get("channel") or "").strip()
        description = str(raw.get("description") or "").strip()
        if channel not in {"event", "file", "visual"}:
            raise ScenarioValidationError(
                f"assertion channel '{channel}' is not one of "
                "{event,file,visual}"
            )
        if not description:
            raise ScenarioValidationError(
                "assertion is missing 'description' (used in the report)"
            )
        return Assertion(
            channel=channel,
            description=description,
            args=dict(raw.get("args") or {}),
            expect_pass=bool(raw.get("expect_pass", True)),
        )


@dataclass(frozen=True)
class Scenario:
    """A complete scenario definition.

    Scenarios are loaded lazily; ``source_path`` is preserved so reports can
    cite where each rule lives.
    """

    id: str
    title: str
    tags: tuple[str, ...]
    setup: Mapping[str, Any]
    steps: tuple[Step, ...]
    assertions: tuple[Assertion, ...]
    source_path: Path | None = None

    def __post_init__(self) -> None:
        if not self.id:
            raise ScenarioValidationError("scenario.id is required")
        if not self.title:
            raise ScenarioValidationError("scenario.title is required")
        if not self.steps:
            raise ScenarioValidationError(
                "scenario.steps must contain at least one step"
            )
        if not self.assertions:
            raise ScenarioValidationError(
                "scenario.assertions must contain at least one assertion"
            )


class ScenarioValidationError(ValueError):
    """Raised when a scenario YAML/JSON fails validation."""


# ---------------------------------------------------------------------------
# Loader
# ---------------------------------------------------------------------------


def load_scenario(path: str | Path) -> Scenario:
    """Parse a scenario file from ``path``.

    Supports ``.json`` natively and ``.yaml``/``.yml`` when ``PyYAML`` is
    installed. Raises :class:`ScenarioValidationError` on malformed input.
    """

    source = Path(path).expanduser().resolve()
    suffix = source.suffix.lower()
    if suffix in {".json"}:
        raw = json.loads(source.read_text(encoding="utf-8"))
    elif suffix in {".yaml", ".yml"}:
        raw = _load_yaml(source)
    else:
        raise ScenarioValidationError(
            f"unsupported scenario file extension '{suffix}'; "
            "expected .json, .yaml or .yml"
        )

    if not isinstance(raw, Mapping):
        raise ScenarioValidationError(
            "scenario file must be a mapping (object) at the top level"
        )

    return _build_scenario(raw, source_path=source)


def loads_scenario(payload: str, *, fmt: str = "json") -> Scenario:
    """Parse a scenario from an in-memory string. Useful in tests."""

    fmt = fmt.lower()
    if fmt == "json":
        raw = json.loads(payload)
    elif fmt in {"yaml", "yml"}:
        raw = _load_yaml_text(payload)
    else:
        raise ScenarioValidationError(f"unsupported scenario fmt '{fmt}'")

    if not isinstance(raw, Mapping):
        raise ScenarioValidationError(
            "scenario payload must be a mapping (object) at the top level"
        )
    return _build_scenario(raw, source_path=None)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _build_scenario(
    raw: Mapping[str, Any], *, source_path: Path | None
) -> Scenario:
    try:
        steps_raw = list(raw.get("steps") or [])
        assertions_raw = list(raw.get("assertions") or [])
    except TypeError as exc:
        raise ScenarioValidationError(
            "scenario.steps and scenario.assertions must be lists"
        ) from exc

    steps = tuple(Step.from_mapping(s) for s in steps_raw)
    assertions = tuple(Assertion.from_mapping(a) for a in assertions_raw)
    tags_raw: Sequence[Any] = raw.get("tags") or ()
    tags = tuple(str(tag) for tag in tags_raw)

    return Scenario(
        id=str(raw.get("id") or "").strip(),
        title=str(raw.get("title") or "").strip(),
        tags=tags,
        setup=dict(raw.get("setup") or {}),
        steps=steps,
        assertions=assertions,
        source_path=source_path,
    )


def _optional_str(raw: Mapping[str, Any], key: str) -> str | None:
    value = raw.get(key)
    if value is None:
        return None
    return str(value)


def _optional_float(raw: Mapping[str, Any], key: str) -> float | None:
    value = raw.get(key)
    if value is None:
        return None
    return float(value)


def _load_yaml(source: Path) -> Any:
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover - exercised when yaml missing
        raise ScenarioValidationError(
            "PyYAML is required to load YAML scenarios; "
            "install via `pip install pyyaml` or provide a JSON scenario."
        ) from exc
    return yaml.safe_load(source.read_text(encoding="utf-8"))


def _load_yaml_text(payload: str) -> Any:
    try:
        import yaml  # type: ignore[import-not-found]
    except ImportError as exc:  # pragma: no cover
        raise ScenarioValidationError(
            "PyYAML is required to load YAML scenarios"
        ) from exc
    return yaml.safe_load(payload)
