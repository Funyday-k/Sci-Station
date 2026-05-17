"""Probe channel #1: read & query the App's debug event log.

The Sci-Station App appends one JSON object per line to
``<researchRoot>/.sci-station/debug/app_events.jsonl`` (see
``AppDebugEventLogger.relativePath``). The orchestrator polls/tails this
file rather than calling into the App, which keeps the App's runtime
behavior identical to a normal user session.

This module never *writes* events; it is strictly an observer.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Mapping

import json
import time


# Mirrors `Sci-Station/Agent/AppDebugEventLogger.swift::relativePath`. Kept as
# a constant so future renames stay searchable.
APP_EVENTS_RELATIVE_PATH = ".sci-station/debug/app_events.jsonl"


@dataclass(frozen=True)
class DebugEvent:
    """One row from ``app_events.jsonl``."""

    raw: Mapping[str, Any]

    @property
    def event(self) -> str:
        return str(self.raw.get("event") or "")

    @property
    def workspace_id(self) -> str | None:
        value = self.raw.get("workspaceID")
        return None if value is None else str(value)

    @property
    def project_id(self) -> str | None:
        value = self.raw.get("projectID")
        return None if value is None else str(value)

    @property
    def thread_id(self) -> str | None:
        value = self.raw.get("threadID")
        return None if value is None else str(value)

    @property
    def run_id(self) -> str | None:
        value = self.raw.get("runID")
        return None if value is None else str(value)

    @property
    def payload(self) -> Mapping[str, Any]:
        payload = self.raw.get("payload")
        if isinstance(payload, Mapping):
            return payload
        return {}

    @property
    def recorded_at(self) -> float | None:
        value = self.raw.get("recordedAt") or self.raw.get("timestamp")
        if value is None:
            return None
        try:
            return float(value)
        except (TypeError, ValueError):
            return None


@dataclass(frozen=True)
class EventQuery:
    """Declarative match used by scenario assertions.

    Multiple fields are combined with logical AND. ``payload_contains`` is a
    *partial* match: every key/value in the query must equal the same key in
    the event payload, but extra payload keys are tolerated.
    """

    event: str
    workspace_id: str | None = None
    project_id: str | None = None
    thread_id: str | None = None
    run_id: str | None = None
    payload_contains: Mapping[str, Any] = field(default_factory=dict)

    def matches(self, ev: DebugEvent) -> bool:
        if self.event and ev.event != self.event:
            return False
        if self.workspace_id is not None and ev.workspace_id != self.workspace_id:
            return False
        if self.project_id is not None and ev.project_id != self.project_id:
            return False
        if self.thread_id is not None and ev.thread_id != self.thread_id:
            return False
        if self.run_id is not None and ev.run_id != self.run_id:
            return False
        for key, expected in self.payload_contains.items():
            if ev.payload.get(key) != expected:
                return False
        return True


class EventLogProbe:
    """Read / tail / query the workspace-local event log."""

    def __init__(self, research_root: str | Path) -> None:
        self.research_root = Path(research_root).expanduser().resolve()

    @property
    def log_path(self) -> Path:
        return self.research_root / APP_EVENTS_RELATIVE_PATH

    # -- iteration -----------------------------------------------------------

    def read_all(self) -> list[DebugEvent]:
        """Return every parsed line in the current log file.

        Malformed lines are silently skipped; callers that need strict
        validation should invoke :meth:`iter_lines` directly.
        """

        return list(self._iter_events(self.log_path))

    def filter(self, query: EventQuery) -> list[DebugEvent]:
        return [ev for ev in self.read_all() if query.matches(ev)]

    def has(self, query: EventQuery) -> bool:
        return any(query.matches(ev) for ev in self.read_all())

    def wait_for(
        self,
        query: EventQuery,
        *,
        timeout_seconds: float = 10.0,
        poll_interval: float = 0.1,
    ) -> DebugEvent | None:
        """Poll the log until ``query`` matches or ``timeout_seconds``.

        Returns the matching event or ``None`` if the timeout elapses. The
        poll uses cheap stat() to skip re-parsing when the file hasn't grown.
        """

        deadline = time.monotonic() + max(0.0, timeout_seconds)
        last_size = -1
        cached: list[DebugEvent] = []
        while time.monotonic() <= deadline:
            current_size = (
                self.log_path.stat().st_size if self.log_path.exists() else 0
            )
            if current_size != last_size:
                cached = self.read_all()
                last_size = current_size
            for ev in cached:
                if query.matches(ev):
                    return ev
            time.sleep(poll_interval)
        return None

    # -- iteration helpers ---------------------------------------------------

    def iter_lines(self, path: Path | None = None) -> Iterable[str]:
        target = path or self.log_path
        if not target.exists():
            return iter(())
        return _iter_text_lines(target)

    def _iter_events(self, path: Path) -> Iterable[DebugEvent]:
        for line in self.iter_lines(path):
            line = line.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, Mapping):
                yield DebugEvent(raw=payload)


def _iter_text_lines(path: Path) -> Iterable[str]:
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            yield line
