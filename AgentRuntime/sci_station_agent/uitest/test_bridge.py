"""Client for the App-side UI Test Bridge (P-AT.1e).

The bridge is a DEBUG-only Unix-domain socket opened by Sci-Station when
the App is launched with ``--uitest-bridge`` or
``SCI_STATION_TEST_BRIDGE_SOCKET``. Each connection sends one JSON request
terminated by ``\n`` and receives one JSON response terminated by ``\n``.

Wire request::

    {"command": "library.import.attachFixturePDF", "args": {"fixture_id": "x"}}

Wire response::

    {"ok": true, "result": {...}}

Only whitelisted commands are accepted App-side. This client intentionally
has no generic "eval" or shell-like escape hatch.
"""

from __future__ import annotations

import json
import socket
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping, Protocol


class TestBridgeError(RuntimeError):
    """Raised when the Test Bridge command cannot be delivered or fails."""


TestBridgeError.__test__ = False


class TestBridgeClient(Protocol):
    """Protocol consumed by UI drivers for ``test_bridge`` steps."""

    def send(self, command: str, args: Mapping[str, Any] | None = None) -> dict[str, Any]: ...


TestBridgeClient.__test__ = False


@dataclass(frozen=True)
class UnixSocketTestBridgeClient:
    """One-command-per-connection Unix-domain socket client."""

    socket_path: str | Path
    timeout_seconds: float = 10.0

    def send(self, command: str, args: Mapping[str, Any] | None = None) -> dict[str, Any]:
        request = {"command": command, "args": dict(args or {})}
        raw_request = json.dumps(request, separators=(",", ":")).encode("utf-8") + b"\n"
        path = str(Path(self.socket_path).expanduser())
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                sock.settimeout(self.timeout_seconds)
                sock.connect(path)
                sock.sendall(raw_request)
                raw_response = _read_line(sock)
        except OSError as exc:
            raise TestBridgeError(f"test bridge socket error: {exc}") from exc

        try:
            payload = json.loads(raw_response.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise TestBridgeError(
                f"test bridge returned non-JSON response: {raw_response!r}"
            ) from exc
        if not isinstance(payload, dict):
            raise TestBridgeError(f"test bridge returned non-object response: {payload!r}")
        if not payload.get("ok"):
            raise TestBridgeError(str(payload.get("error") or "unknown bridge error"))
        result = payload.get("result") or {}
        if not isinstance(result, dict):
            raise TestBridgeError(f"test bridge returned non-object result: {result!r}")
        return result

    def ping(self) -> dict[str, Any]:
        return self.send("ping")


@dataclass
class StubTestBridgeClient:
    """Scriptable test double used by driver/unit tests."""

    results: list[dict[str, Any]] = field(default_factory=list)
    errors: list[Exception] = field(default_factory=list)
    sent: list[tuple[str, dict[str, Any]]] = field(default_factory=list)

    def send(self, command: str, args: Mapping[str, Any] | None = None) -> dict[str, Any]:
        self.sent.append((command, dict(args or {})))
        if self.errors:
            raise self.errors.pop(0)
        if self.results:
            return self.results.pop(0)
        return {}


def _read_line(sock: socket.socket, *, max_bytes: int = 1_048_576) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while total < max_bytes:
        chunk = sock.recv(4096)
        if not chunk:
            break
        newline = chunk.find(b"\n")
        if newline >= 0:
            chunks.append(chunk[:newline])
            return b"".join(chunks)
        chunks.append(chunk)
        total += len(chunk)
    if not chunks:
        raise TestBridgeError("test bridge closed without a response")
    return b"".join(chunks)


__all__ = [
    "StubTestBridgeClient",
    "TestBridgeClient",
    "TestBridgeError",
    "UnixSocketTestBridgeClient",
]
