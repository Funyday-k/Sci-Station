"""Tests for the Python-side Test Bridge client."""

from __future__ import annotations

import json
import socket
import tempfile
import threading
import time
from pathlib import Path

import pytest

from sci_station_agent.uitest.test_bridge import (
    StubTestBridgeClient,
    TestBridgeError,
    UnixSocketTestBridgeClient,
)


def _serve_once(path: Path, response: dict[str, object], received: list[dict[str, object]]) -> threading.Thread:
    def run() -> None:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
            server.bind(str(path))
            server.listen(1)
            conn, _ = server.accept()
            with conn:
                raw = b""
                while not raw.endswith(b"\n"):
                    raw += conn.recv(4096)
                received.append(json.loads(raw.decode("utf-8")))
                conn.sendall(json.dumps(response).encode("utf-8") + b"\n")

    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    deadline = time.monotonic() + 2.0
    while not path.exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    return thread


def _short_socket_path() -> Path:
    return Path(tempfile.mkdtemp(prefix="sstb-", dir="/tmp")) / "b.sock"


def test_unix_socket_client_sends_command_and_returns_result() -> None:
    socket_path = _short_socket_path()
    received: list[dict[str, object]] = []
    thread = _serve_once(
        socket_path,
        {"ok": True, "result": {"paper_id": "p1"}},
        received,
    )

    client = UnixSocketTestBridgeClient(socket_path)
    result = client.send("library.import.attachFixturePDF", {"fixture_id": "p1"})

    thread.join(timeout=2)
    assert result == {"paper_id": "p1"}
    assert received == [
        {
            "command": "library.import.attachFixturePDF",
            "args": {"fixture_id": "p1"},
        }
    ]


def test_unix_socket_client_maps_app_error() -> None:
    socket_path = _short_socket_path()
    thread = _serve_once(socket_path, {"ok": False, "error": "bad command"}, [])

    client = UnixSocketTestBridgeClient(socket_path)
    with pytest.raises(TestBridgeError) as exc_info:
        client.send("bad")

    thread.join(timeout=2)
    assert "bad command" in str(exc_info.value)


def test_stub_bridge_client_records_calls() -> None:
    stub = StubTestBridgeClient(results=[{"entry_id": "q1"}])

    result = stub.send("library.import.attachFixturePDF", {"paper_id": "p1"})

    assert result == {"entry_id": "q1"}
    assert stub.sent == [("library.import.attachFixturePDF", {"paper_id": "p1"})]
