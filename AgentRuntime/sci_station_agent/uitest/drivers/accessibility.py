"""Real :class:`UIDriver` backed by the SciStationUIProbe Swift helper.

The Python orchestrator never calls macOS Accessibility APIs directly.
Instead it spawns ``Tools/SciStationUIProbe`` (built via ``swift build``)
as a child process and exchanges NDJSON requests over its stdio pipes.
See ``Tools/SciStationUIProbe/main.swift`` for the wire protocol contract.

The driver supports three transports so the same class is used in real
and test environments:

* :class:`SubprocessTransport` -- production. Spawns the probe binary and
  pipes stdin/stdout.
* :class:`PipeTransport` -- accepts pre-existing ``BufferedReader`` /
  ``BufferedWriter`` handles. Useful for unit tests that hand the driver
  a synthetic pair created with ``os.pipe`` / ``io.BytesIO``.
* Any user-supplied object implementing :class:`Transport`.

Usage::

    driver = AccessibilityDriver(bundle_id="Lingyu-Xia.Sci-Station")
    runner = ScenarioRunner(research_root, driver=driver)
    result = runner.run(scenario)
    driver.close()

In CI / debug builds where the test runner does not have Accessibility
permission, every command returns ``ok=false`` with the error
``"AXError=-25204"`` (kAXErrorAPIDisabled). The driver bubbles this up as
:class:`DriverError` so the scenario reports the underlying permission
problem, not a generic "click failed".
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, IO, Mapping, Protocol

from sci_station_agent.uitest.drivers.base import DriverError


DEFAULT_BUNDLE_ID = "Lingyu-Xia.Sci-Station"
DEFAULT_TIMEOUT_MS = 4_000


class Transport(Protocol):
    """A line-oriented JSON transport (stdin/stdout of the probe)."""

    def send_line(self, line: str) -> None: ...

    def recv_line(self) -> str: ...

    def close(self) -> None: ...


# ---------------------------------------------------------------------------
# Concrete transports
# ---------------------------------------------------------------------------


class SubprocessTransport:
    """Spawns the SciStationUIProbe binary and pipes its stdio."""

    def __init__(self, probe_path: Path) -> None:
        if not probe_path.exists():
            raise FileNotFoundError(
                f"SciStationUIProbe binary not found at '{probe_path}'."
                " Build it with: swift build --product SciStationUIProbe"
            )
        self._process = subprocess.Popen(  # noqa: S603 - probe path is validated
            [str(probe_path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False,
            bufsize=0,
        )
        # The pipes are guaranteed non-None because we requested all three.
        assert self._process.stdin is not None
        assert self._process.stdout is not None
        self._stdin: IO[bytes] = self._process.stdin
        self._stdout: IO[bytes] = self._process.stdout
        self._lock = threading.Lock()

    def send_line(self, line: str) -> None:
        with self._lock:
            payload = line.rstrip("\n").encode("utf-8") + b"\n"
            self._stdin.write(payload)
            self._stdin.flush()

    def recv_line(self) -> str:
        raw = self._stdout.readline()
        if not raw:
            stderr = b""
            if self._process.stderr is not None:
                try:
                    stderr = self._process.stderr.read()
                except Exception:
                    stderr = b""
            raise DriverError(
                "SciStationUIProbe closed its stdout unexpectedly"
                + (f"; stderr={stderr.decode('utf-8', errors='replace')!r}" if stderr else "")
            )
        return raw.decode("utf-8").rstrip("\n")

    def close(self) -> None:
        if self._process.poll() is not None:
            return
        try:
            self.send_line(json.dumps({"cmd": "quit"}))
            # Drain the goodbye response then wait briefly.
            try:
                _ = self.recv_line()
            except DriverError:
                pass
        finally:
            try:
                self._process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self._process.terminate()
                try:
                    self._process.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    self._process.kill()


class PipeTransport:
    """Backed by an explicit reader/writer pair, useful for tests."""

    def __init__(self, reader: IO[str], writer: IO[str]) -> None:
        self._reader = reader
        self._writer = writer

    def send_line(self, line: str) -> None:
        self._writer.write(line.rstrip("\n") + "\n")
        self._writer.flush()

    def recv_line(self) -> str:
        raw = self._reader.readline()
        if raw == "":
            raise DriverError("transport closed before response was read")
        return raw.rstrip("\n")

    def close(self) -> None:
        for handle in (self._reader, self._writer):
            try:
                handle.close()
            except Exception:
                pass


@dataclass
class _Recorded:
    """One round-trip request/response pair recorded by :class:`StubTransport`."""

    request: dict[str, Any]
    response: dict[str, Any]


class StubTransport:
    """Test double that returns scripted responses in FIFO order.

    The driver writes commands to ``sent``; the test feeds responses via
    :meth:`enqueue`. Useful for unit-testing the driver's framing and
    error mapping without spawning a subprocess.
    """

    def __init__(self) -> None:
        self.sent: list[dict[str, Any]] = []
        self._responses: list[dict[str, Any]] = []
        self.recorded: list[_Recorded] = []
        self.closed = False

    def enqueue(self, response: Mapping[str, Any]) -> None:
        self._responses.append(dict(response))

    def send_line(self, line: str) -> None:
        payload = json.loads(line)
        if not isinstance(payload, dict):
            raise AssertionError("driver sent non-object JSON")
        self.sent.append(payload)

    def recv_line(self) -> str:
        if not self._responses:
            raise DriverError("StubTransport ran out of scripted responses")
        response = self._responses.pop(0)
        if self.sent:
            self.recorded.append(_Recorded(request=self.sent[-1], response=response))
        return json.dumps(response)

    def close(self) -> None:
        self.closed = True


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def _default_probe_path() -> Path | None:
    """Best-effort lookup of the built probe binary."""

    env = os.environ.get("SCI_STATION_UI_PROBE")
    if env:
        return Path(env)
    candidate = (
        Path(__file__).resolve().parents[4] / ".build" / "debug" / "SciStationUIProbe"
    )
    if candidate.exists():
        return candidate
    on_path = shutil.which("SciStationUIProbe")
    if on_path:
        return Path(on_path)
    return None


@dataclass
class AccessibilityDriver:
    """UIDriver implementation that talks to the SciStationUIProbe."""

    bundle_id: str = DEFAULT_BUNDLE_ID
    default_timeout_ms: int = DEFAULT_TIMEOUT_MS
    transport: Transport | None = None
    probe_path: Path | None = None
    _owns_transport: bool = field(default=False, init=False, repr=False)

    def __post_init__(self) -> None:
        if self.transport is None:
            probe = self.probe_path or _default_probe_path()
            if probe is None:
                raise FileNotFoundError(
                    "SciStationUIProbe binary could not be located. Pass "
                    "probe_path=… or set SCI_STATION_UI_PROBE."
                )
            self.transport = SubprocessTransport(probe)
            self._owns_transport = True

    # -- protocol surface ----------------------------------------------------

    def click(self, accessibility_id: str) -> None:
        self._call({"cmd": "click", "bundle": self.bundle_id, "axid": accessibility_id})

    def type_text(self, accessibility_id: str, text: str) -> None:
        self._call(
            {
                "cmd": "type",
                "bundle": self.bundle_id,
                "axid": accessibility_id,
                "value": text,
            }
        )

    def drag(self, source_id: str, target_id: str) -> None:
        raise DriverError(
            "AccessibilityDriver does not implement drag yet; "
            "drag-and-drop scenarios are deferred to P-AT.3b."
        )

    def send_test_bridge(self, command: str, args: Mapping[str, Any]) -> None:
        raise DriverError(
            "AccessibilityDriver cannot deliver test_bridge commands; the "
            "in-app Test Bridge socket (P-AT.1e) is not implemented yet."
        )

    # -- additional helpers (not part of UIDriver) ---------------------------

    def ping(self) -> str:
        return str(self._call({"cmd": "ping"})["version"])

    def is_trusted(self) -> bool:
        return bool(self._call({"cmd": "permission"})["trusted"])

    def find(self, accessibility_id: str, *, timeout_ms: int | None = None) -> dict[str, Any]:
        response = self._call(
            {
                "cmd": "find",
                "bundle": self.bundle_id,
                "axid": accessibility_id,
                "timeout_ms": timeout_ms if timeout_ms is not None else self.default_timeout_ms,
            }
        )
        return dict(response)

    def tree(self, *, max_depth: int = 4) -> dict[str, Any]:
        response = self._call(
            {"cmd": "tree", "bundle": self.bundle_id, "max_depth": max_depth}
        )
        return dict(response.get("tree") or {})

    def launch(self, *, args: list[str] | None = None, wait: bool = True) -> int:
        request: dict[str, Any] = {"cmd": "launch", "bundle": self.bundle_id, "wait": wait}
        if args is not None:
            request["args"] = list(args)
        return int(self._call(request)["pid"])

    def terminate(self) -> None:
        self._call({"cmd": "terminate", "bundle": self.bundle_id})

    def close(self) -> None:
        if self.transport is None:
            return
        if self._owns_transport:
            self.transport.close()
        self.transport = None

    # -- internals -----------------------------------------------------------

    def _call(self, request: Mapping[str, Any]) -> dict[str, Any]:
        if self.transport is None:
            raise DriverError("AccessibilityDriver is closed")
        self.transport.send_line(json.dumps(request))
        raw = self.transport.recv_line()
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise DriverError(f"probe returned non-JSON line: {raw!r}") from exc
        if not isinstance(payload, dict):
            raise DriverError(f"probe returned non-object JSON: {raw!r}")
        if not payload.get("ok"):
            error = payload.get("error") or "unknown probe error"
            raise DriverError(f"{request.get('cmd', '?')}: {error}")
        return payload


__all__ = [
    "AccessibilityDriver",
    "PipeTransport",
    "StubTransport",
    "SubprocessTransport",
    "Transport",
    "DEFAULT_BUNDLE_ID",
]
