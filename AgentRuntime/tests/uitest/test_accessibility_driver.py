"""Unit tests for :class:`AccessibilityDriver` (P-AT.3a).

The real driver talks to ``Tools/SciStationUIProbe`` over a subprocess
pipe. These tests substitute a :class:`StubTransport` so the framing /
error-mapping layer can be verified without requiring the probe binary,
the Sci-Station app, or Accessibility permission.

The Swift probe itself is unit-tested separately via the script in
``tests/uitest/test_accessibility_probe_smoke.py`` (executes the built
probe with ``cmd: ping`` / ``cmd: permission`` so the wire protocol stays
in sync between the two halves).
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from sci_station_agent.uitest.drivers.accessibility import (
    AccessibilityDriver,
    DEFAULT_BUNDLE_ID,
    StubTransport,
)
from sci_station_agent.uitest.drivers.base import DriverError
from sci_station_agent.uitest.test_bridge import StubTestBridgeClient, TestBridgeError


@pytest.fixture()
def stub_driver() -> tuple[AccessibilityDriver, StubTransport]:
    transport = StubTransport()
    driver = AccessibilityDriver(transport=transport, bundle_id="com.example.Test")
    return driver, transport


def test_click_emits_well_formed_request(stub_driver) -> None:
    driver, transport = stub_driver
    transport.enqueue({"ok": True})

    driver.click("library.import.button")

    assert transport.sent == [
        {
            "cmd": "click",
            "bundle": "com.example.Test",
            "axid": "library.import.button",
        }
    ]


def test_type_text_includes_value_field(stub_driver) -> None:
    driver, transport = stub_driver
    transport.enqueue({"ok": True})

    driver.type_text("search.field", "graph theory")

    request = transport.sent[-1]
    assert request["cmd"] == "type"
    assert request["axid"] == "search.field"
    assert request["value"] == "graph theory"


def test_find_returns_payload_subset(stub_driver) -> None:
    driver, transport = stub_driver
    transport.enqueue(
        {"ok": True, "found": True, "role": "AXButton", "title": "Import"}
    )

    result = driver.find("library.import.button")

    assert result["found"] is True
    assert result["role"] == "AXButton"
    assert result["title"] == "Import"


def test_tree_returns_tree_dict(stub_driver) -> None:
    driver, transport = stub_driver
    transport.enqueue(
        {
            "ok": True,
            "tree": {
                "role": "AXApplication",
                "children": [{"role": "AXWindow", "title": "Sci-Station"}],
            },
        }
    )

    tree = driver.tree(max_depth=2)

    assert tree["role"] == "AXApplication"
    assert tree["children"][0]["title"] == "Sci-Station"


def test_probe_error_maps_to_driver_error(stub_driver) -> None:
    driver, transport = stub_driver
    transport.enqueue({"ok": False, "error": "element not found for axid 'foo'"})

    with pytest.raises(DriverError) as exc_info:
        driver.click("foo")

    assert "element not found" in str(exc_info.value)


def test_non_json_response_is_reported_clearly(stub_driver) -> None:
    driver, transport = stub_driver
    # Bypass enqueue to inject garbage as the next "response".
    transport._responses.append(None)  # type: ignore[arg-type]

    with pytest.raises(DriverError) as exc_info:
        driver.click("foo")

    assert "non-object JSON" in str(exc_info.value) or "non-JSON" in str(exc_info.value)


def test_drag_emits_well_formed_request(stub_driver) -> None:
    driver, transport = stub_driver
    transport.enqueue({"ok": True})

    driver.drag("queue.row.a", "queue.row.b")

    assert transport.sent == [
        {
            "cmd": "drag",
            "bundle": "com.example.Test",
            "source_axid": "queue.row.a",
            "target_axid": "queue.row.b",
        }
    ]


def test_send_test_bridge_requires_client(stub_driver) -> None:
    driver, _ = stub_driver
    with pytest.raises(DriverError) as exc_info:
        driver.send_test_bridge("library.import.attachFixturePDF", {"id": "x"})
    assert "TestBridgeClient" in str(exc_info.value)


def test_send_test_bridge_delegates_to_client() -> None:
    bridge = StubTestBridgeClient(results=[{"paper_id": "p1"}])
    driver = AccessibilityDriver(
        transport=StubTransport(),
        bundle_id="com.example.Test",
        test_bridge=bridge,
    )

    driver.send_test_bridge("library.import.attachFixturePDF", {"fixture_id": "p1"})

    assert bridge.sent == [
        ("library.import.attachFixturePDF", {"fixture_id": "p1"})
    ]


def test_send_test_bridge_maps_bridge_error_to_driver_error() -> None:
    bridge = StubTestBridgeClient(errors=[TestBridgeError("boom")])
    driver = AccessibilityDriver(
        transport=StubTransport(),
        bundle_id="com.example.Test",
        test_bridge=bridge,
    )

    with pytest.raises(DriverError) as exc_info:
        driver.send_test_bridge("queue.append", {"paper_id": "p1"})

    assert "boom" in str(exc_info.value)


def test_close_marks_transport_closed_when_owned() -> None:
    transport = StubTransport()
    # Pass transport but pretend we own it — exercises the ownership branch.
    driver = AccessibilityDriver(transport=transport, bundle_id="com.example.Test")
    driver._owns_transport = True  # type: ignore[attr-defined]
    driver.close()
    assert transport.closed is True


def test_default_bundle_id_constant_matches_app() -> None:
    # If the project's PRODUCT_BUNDLE_IDENTIFIER changes the driver default
    # must change too; this test fails loudly so the docs / probe stay in
    # sync with the Xcode project.
    assert DEFAULT_BUNDLE_ID == "Lingyu-Xia.Sci-Station"


# ---------------------------------------------------------------------------
# Optional smoke test against the real Swift probe.
#
# This test is skipped unless the binary exists at the conventional location
# (``.build/debug/SciStationUIProbe``). When it does, we exercise ``ping``
# and ``permission`` end-to-end so a wire-protocol regression in the Swift
# side fails Python tests too.
# ---------------------------------------------------------------------------


_PROBE_PATH = Path(__file__).resolve().parents[3] / ".build" / "debug" / "SciStationUIProbe"


@pytest.mark.skipif(
    not _PROBE_PATH.exists(),
    reason=(
        "SciStationUIProbe binary not built. Build with: "
        "swift build --product SciStationUIProbe"
    ),
)
def test_real_probe_responds_to_ping_and_permission() -> None:
    # Run the probe with two real commands and verify the framing on stdout.
    proc = subprocess.run(  # noqa: S603
        [str(_PROBE_PATH)],
        input='{"cmd":"ping"}\n{"cmd":"permission"}\n{"cmd":"quit"}\n',
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert proc.returncode == 0, proc.stderr
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    assert len(lines) == 3, proc.stdout
    ping_response = json.loads(lines[0])
    permission_response = json.loads(lines[1])
    assert ping_response["ok"] is True
    assert "version" in ping_response
    assert permission_response["ok"] is True
    # Accessibility permission is granted/denied per binary; we don't assert
    # on the boolean, only that the field round-trips.
    assert "trusted" in permission_response


@pytest.mark.skipif(
    shutil.which("swift") is None,
    reason="swift toolchain unavailable in this environment",
)
def test_probe_path_helper_finds_built_binary_when_present() -> None:
    # This test is a sanity check that ``_default_probe_path`` succeeds
    # whenever the canonical build location holds a binary.
    from sci_station_agent.uitest.drivers.accessibility import _default_probe_path

    found = _default_probe_path()
    if _PROBE_PATH.exists():
        assert found is not None
        assert found.exists()
