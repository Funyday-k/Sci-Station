"""Driver protocol used by :class:`ScenarioRunner`.

Drivers translate scenario steps (``click``, ``type``, ``drag``, …) into
real OS-level actions. We deliberately model this as a duck-typed protocol
rather than an ABC so test fakes stay trivial.
"""

from __future__ import annotations

from typing import Any, Mapping, Protocol


class DriverError(RuntimeError):
    """Raised when a driver cannot perform a requested action."""


class UIDriver(Protocol):
    """Minimal contract a driver must satisfy."""

    def click(self, accessibility_id: str) -> None:
        ...

    def type_text(self, accessibility_id: str, text: str) -> None:
        ...

    def drag(self, source_id: str, target_id: str) -> None:
        ...

    def send_test_bridge(self, command: str, args: Mapping[str, Any]) -> None:
        ...


class NullDriver:
    """Records each call to a list. Suitable for unit tests / dry runs.

    The orchestrator's logic can be exercised end-to-end against this driver
    by populating the workspace's ``app_events.jsonl`` and YAML files in the
    test setup directly, then running the scenario.
    """

    def __init__(self) -> None:
        self.actions: list[tuple[str, tuple[Any, ...], Mapping[str, Any]]] = []

    def click(self, accessibility_id: str) -> None:
        self.actions.append(("click", (accessibility_id,), {}))

    def type_text(self, accessibility_id: str, text: str) -> None:
        self.actions.append(("type_text", (accessibility_id, text), {}))

    def drag(self, source_id: str, target_id: str) -> None:
        self.actions.append(("drag", (source_id, target_id), {}))

    def send_test_bridge(self, command: str, args: Mapping[str, Any]) -> None:
        self.actions.append(("send_test_bridge", (command,), dict(args)))
