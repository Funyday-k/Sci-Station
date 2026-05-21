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
import select
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, IO, Mapping, Protocol

from sci_station_agent.uitest.drivers.base import DriverError
from sci_station_agent.uitest.test_bridge import TestBridgeClient, TestBridgeError


DEFAULT_BUNDLE_ID = "Lingyu-Xia.Sci-Station"
DEFAULT_TIMEOUT_MS = 4_000
DEFAULT_PROBE_READ_TIMEOUT_S = 8.0


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

    def __init__(
        self,
        probe_path: Path,
        *,
        read_timeout_s: float = DEFAULT_PROBE_READ_TIMEOUT_S,
    ) -> None:
        if not probe_path.exists():
            raise FileNotFoundError(
                f"SciStationUIProbe binary not found at '{probe_path}'."
                " Build it with: swift build --product SciStationUIProbe"
            )
        self._read_timeout_s = read_timeout_s
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
        self._stdout_fd = self._stdout.fileno()
        self._read_buffer = bytearray()
        self._lock = threading.Lock()

    def send_line(self, line: str) -> None:
        with self._lock:
            payload = line.rstrip("\n").encode("utf-8") + b"\n"
            try:
                self._stdin.write(payload)
                self._stdin.flush()
            except BrokenPipeError as exc:
                raise DriverError("SciStationUIProbe stdin closed unexpectedly") from exc

    def recv_line(self) -> str:
        deadline = time.monotonic() + self._read_timeout_s
        while True:
            newline_index = self._read_buffer.find(b"\n")
            if newline_index >= 0:
                raw = bytes(self._read_buffer[:newline_index])
                del self._read_buffer[: newline_index + 1]
                return raw.decode("utf-8", errors="replace").rstrip("\r")

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise DriverError(
                    "SciStationUIProbe timed out after "
                    f"{self._read_timeout_s:.1f}s waiting for a response line"
                )

            try:
                ready, _, _ = select.select([self._stdout_fd], [], [], remaining)
            except (OSError, ValueError) as exc:
                raise DriverError(f"SciStationUIProbe stdout is not readable: {exc}") from exc
            if not ready:
                raise DriverError(
                    "SciStationUIProbe timed out after "
                    f"{self._read_timeout_s:.1f}s waiting for a response line"
                )
            try:
                chunk = os.read(self._stdout_fd, 4096)
            except OSError as exc:
                raise DriverError(f"SciStationUIProbe stdout read failed: {exc}") from exc
            if not chunk:
                stderr = self._read_available_stderr()
                raise DriverError(
                    "SciStationUIProbe closed its stdout unexpectedly"
                    + (
                        f"; stderr={stderr.decode('utf-8', errors='replace')!r}"
                        if stderr
                        else ""
                    )
                )
            self._read_buffer.extend(chunk)

    def _read_available_stderr(self) -> bytes:
        if self._process.stderr is None:
            return b""
        fd = self._process.stderr.fileno()
        chunks: list[bytes] = []
        while True:
            try:
                ready, _, _ = select.select([fd], [], [], 0)
            except (OSError, ValueError):
                break
            if not ready:
                break
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks)

    def close(self) -> None:
        if self._process.poll() is not None:
            return
        self._process.terminate()
        try:
            self._process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            self._process.kill()
            try:
                self._process.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                pass


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
    test_bridge: TestBridgeClient | None = None
    probe_path: Path | None = None
    probe_read_timeout_s: float = DEFAULT_PROBE_READ_TIMEOUT_S
    _owns_transport: bool = field(default=False, init=False, repr=False)

    def __post_init__(self) -> None:
        if self.transport is None:
            probe = self.probe_path or _default_probe_path()
            if probe is None:
                raise FileNotFoundError(
                    "SciStationUIProbe binary could not be located. Pass "
                    "probe_path=… or set SCI_STATION_UI_PROBE."
                )
            self.transport = SubprocessTransport(
                probe,
                read_timeout_s=self.probe_read_timeout_s,
            )
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
        self._call(
            {
                "cmd": "drag",
                "bundle": self.bundle_id,
                "source_axid": source_id,
                "target_axid": target_id,
            }
        )

    def send_test_bridge(self, command: str, args: Mapping[str, Any]) -> None:
        if self.test_bridge is None:
            raise DriverError(
                "AccessibilityDriver requires a TestBridgeClient for "
                "test_bridge commands. Pass test_bridge=UnixSocketTestBridgeClient(...)."
            )
        try:
            self.test_bridge.send(command, args)
        except TestBridgeError as exc:
            raise DriverError(f"test_bridge({command}) failed: {exc}") from exc

    # -- additional helpers (not part of UIDriver) ---------------------------

    def ping(self) -> str:
        return str(self._call({"cmd": "ping"})["version"])

    def list_running(self) -> list[dict[str, Any]]:
        apps = self._call({"cmd": "list_running"}).get("apps")
        if not isinstance(apps, list):
            return []
        return [dict(app) for app in apps if isinstance(app, dict)]

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
