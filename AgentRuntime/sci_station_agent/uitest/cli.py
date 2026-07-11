"""One-shot CLI that runs a YAML scenario against the real macOS app.

Wires together the scenario runner, UI driver, event probe, and file probe so an engineer can
verify a scenario end-to-end without remembering every flag:

* ``Tools/SciStationUIProbe`` (built via ``swift build --product
  SciStationUIProbe``) is launched as a child process and used as the
  AccessibilityDriver transport.
* ``Sci-Station.app`` (Debug build) is launched via the probe with
  ``--uitest-bridge --uitest-bridge-socket <path>`` so its Unix-domain
  bridge server starts.
* The CLI polls the bridge until it responds to ``ping``, then sends
  ``workspace.open`` so the app points at our deterministic research root.
* The scenario is executed with :class:`ScenarioRunner`; assertions read
  the same research root the app is now writing into.

Usage::

    .venv/bin/python -m sci_station_agent.uitest.cli \\
        AgentRuntime/sci_station_agent/uitest/scenarios/MT03-01_wiki_rename.yaml

The script exits 0 on a passing scenario and non-zero otherwise. Pass
``--keep-research-root`` to inspect the workspace after the run.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

from sci_station_agent.uitest.drivers.accessibility import (
    DEFAULT_BUNDLE_ID,
    AccessibilityDriver,
    _default_probe_path,
)
from sci_station_agent.uitest.drivers.base import DriverError
from sci_station_agent.uitest.runner import ScenarioRunner
from sci_station_agent.uitest.scenario import load_scenario
from sci_station_agent.uitest.test_bridge import (
    TestBridgeError,
    UnixSocketTestBridgeClient,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _wait_for_bridge(client: UnixSocketTestBridgeClient, *, timeout_s: float) -> None:
    """Block until the app's bridge server replies to ``ping``."""

    deadline = time.monotonic() + timeout_s
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            client.send("ping")
            return
        except (TestBridgeError, FileNotFoundError, ConnectionRefusedError, socket.error) as exc:
            last_error = exc
            time.sleep(0.15)
    raise TimeoutError(
        f"timed out after {timeout_s:.1f}s waiting for the test bridge at "
        f"{client.socket_path}: {last_error!r}"
    )


def _probe_is_accessibility_trusted(probe_path: Path, *, timeout_s: float) -> bool:
    try:
        proc = subprocess.run(
            [str(probe_path)],
            input='{"cmd":"permission"}\n{"cmd":"quit"}\n',
            capture_output=True,
            text=True,
            timeout=max(0.5, timeout_s),
        )
    except subprocess.TimeoutExpired as exc:
        raise DriverError(
            f"SciStationUIProbe permission check timed out after {timeout_s:.1f}s"
        ) from exc
    if proc.returncode != 0:
        raise DriverError(
            "SciStationUIProbe permission check exited with "
            f"{proc.returncode}: {proc.stderr.strip()}"
        )
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    if not lines:
        raise DriverError("SciStationUIProbe permission check returned no output")
    try:
        payload = json.loads(lines[0])
    except json.JSONDecodeError as exc:
        raise DriverError(
            f"SciStationUIProbe permission check returned non-JSON: {lines[0]!r}"
        ) from exc
    if not isinstance(payload, dict) or not payload.get("ok"):
        raise DriverError(
            "SciStationUIProbe permission check failed: "
            f"{payload.get('error') if isinstance(payload, dict) else payload!r}"
        )
    return bool(payload.get("trusted"))


def _wait_until_app_not_running(
    driver: AccessibilityDriver,
    *,
    bundle_id: str,
    timeout_s: float,
) -> None:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        apps = driver.list_running()
        if not any(app.get("bundle") == bundle_id for app in apps):
            return
        time.sleep(0.15)
    raise TimeoutError(f"timed out after {timeout_s:.1f}s waiting for {bundle_id} to terminate")


def _seed_research_root(root: Path) -> None:
    """Create the minimal directory layout an open workspace expects.

    The app itself materialises most of these on first open, but creating
    the wiki/ + .sci-station/debug/ subdirs up-front avoids any first-run
    permission prompts and lets the EventLogProbe see an empty log
    immediately instead of getting FileNotFoundError on every poll.
    """

    (root / "wiki").mkdir(parents=True, exist_ok=True)
    (root / ".sci-station" / "debug").mkdir(parents=True, exist_ok=True)
    log = root / ".sci-station" / "debug" / "app_events.jsonl"
    if not log.exists():
        log.touch()


def _format_summary(summary: dict[str, Any]) -> str:
    lines = [
        f"scenario: {summary['scenario_id']}",
        f"research_root: {summary['research_root']}",
        f"succeeded: {summary['succeeded']}",
        f"steps: {summary['step_count']}",
    ]
    if summary["step_failures"]:
        lines.append("step failures:")
        for failure in summary["step_failures"]:
            lines.append(f"  - {failure['kind']} ({failure.get('target') or '-'}): {failure['detail']}")
    if summary["assertion_failures"]:
        lines.append("assertion failures:")
        for failure in summary["assertion_failures"]:
            lines.append(f"  - [{failure['channel']}] {failure['description']}: {failure['detail']}")
    if summary["notes"]:
        lines.append("notes:")
        for note in summary["notes"]:
            lines.append(f"  - {note}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else None)
    parser.add_argument("scenario", type=Path, help="YAML or JSON scenario path.")
    parser.add_argument(
        "--research-root",
        type=Path,
        default=None,
        help="Research workspace dir. Defaults to a fresh tmpdir.",
    )
    parser.add_argument(
        "--bridge-socket",
        type=Path,
        default=None,
        help="Path used for the Unix bridge socket. Defaults under tmpdir.",
    )
    parser.add_argument(
        "--bundle-id",
        default=DEFAULT_BUNDLE_ID,
        help=f"App bundle id (default: {DEFAULT_BUNDLE_ID}).",
    )
    parser.add_argument(
        "--probe-path",
        type=Path,
        default=None,
        help="Path to SciStationUIProbe. Defaults to .build/debug/SciStationUIProbe.",
    )
    parser.add_argument(
        "--bridge-timeout",
        type=float,
        default=20.0,
        help="Seconds to wait for the bridge server to come up (default 20).",
    )
    parser.add_argument(
        "--probe-read-timeout",
        type=float,
        default=6.0,
        help="Seconds to wait for each SciStationUIProbe response (default 6).",
    )
    parser.add_argument(
        "--keep-research-root",
        action="store_true",
        help="Do not delete the research root after the run (helpful for triage).",
    )
    parser.add_argument(
        "--keep-app-running",
        action="store_true",
        help="Skip terminating the app at the end (helpful for triage).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the summary as JSON instead of human-readable text.",
    )
    args = parser.parse_args(argv)

    scenario_path = args.scenario.expanduser().resolve()
    if not scenario_path.exists():
        parser.error(f"scenario not found: {scenario_path}")

    scenario = load_scenario(scenario_path)

    tmp_root_owned = False
    if args.research_root is None:
        # The app is sandboxed and cannot freely write to /tmp or
        # /var/folders. Stand the research root up inside the container's
        # Documents directory so the sandboxed process can write to it
        # without an explicit user-granted Powerbox file URL.
        sandbox_documents = (
            Path.home()
            / "Library"
            / "Containers"
            / args.bundle_id
            / "Data"
            / "Documents"
        )
        try:
            sandbox_documents.mkdir(parents=True, exist_ok=True)
            tmp_dir = Path(
                tempfile.mkdtemp(prefix="sci-station-uitest-", dir=sandbox_documents)
            )
        except OSError:
            tmp_dir = Path(tempfile.mkdtemp(prefix="sci-station-uitest-"))
        research_root = tmp_dir
        tmp_root_owned = True
    else:
        research_root = args.research_root.expanduser().resolve()
        research_root.mkdir(parents=True, exist_ok=True)

    if args.bridge_socket is None:
        # The app runs sandboxed (com.apple.security.app-sandbox=true), so
        # bind(2) will fail with EPERM on /tmp or any user-owned directory the
        # app has not been granted explicit access to. The sandbox container's
        # own ``Data/tmp`` is always writable by the container's process, so
        # default there. Keep it short — AF_UNIX paths are capped at 104 bytes.
        sandbox_tmp = (
            Path.home()
            / "Library"
            / "Containers"
            / args.bundle_id
            / "Data"
            / "tmp"
        )
        try:
            sandbox_tmp.mkdir(parents=True, exist_ok=True)
        except OSError:
            sandbox_tmp = research_root
        bridge_socket = sandbox_tmp / "uitest-bridge.sock"
    else:
        bridge_socket = args.bridge_socket.expanduser().resolve()
    # AF_UNIX paths are capped at 104 bytes on macOS; bail loudly rather
    # than silently trip the kernel limit deep inside the App.
    if len(str(bridge_socket).encode("utf-8")) >= 104:
        parser.error(
            f"bridge socket path too long ({len(str(bridge_socket))} bytes); "
            "pass --bridge-socket pointing somewhere shorter (e.g. /tmp/<name>.sock)"
        )
    if bridge_socket.exists():
        bridge_socket.unlink()

    _seed_research_root(research_root)

    probe_path = args.probe_path or _default_probe_path()
    if probe_path is None:
        parser.error(
            "SciStationUIProbe binary not found. Build it with: "
            "swift build --product SciStationUIProbe"
        )

    scenario_needs_accessibility = any(
        step.kind in ("click", "type", "drag") for step in scenario.steps
    )
    if scenario_needs_accessibility:
        try:
            trusted = _probe_is_accessibility_trusted(
                probe_path,
                timeout_s=min(args.probe_read_timeout, 3.0),
            )
        except DriverError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        if not trusted:
            print(
                "error: scenario contains click/type/drag steps but the "
                "SciStationUIProbe binary is NOT trusted for macOS "
                "Accessibility. Grant this exact binary under System "
                "Settings -> Privacy & Security -> Accessibility: "
                f"{probe_path}",
                file=sys.stderr,
            )
            return 1

    bridge_client = UnixSocketTestBridgeClient(bridge_socket)

    driver = AccessibilityDriver(
        bundle_id=args.bundle_id,
        test_bridge=bridge_client,
        probe_path=probe_path,
        probe_read_timeout_s=args.probe_read_timeout,
    )

    exit_code = 1
    pid: int | None = None
    try:
        try:
            driver.terminate()
            _wait_until_app_not_running(
                driver,
                bundle_id=args.bundle_id,
                timeout_s=4.0,
            )
        except DriverError:
            pass

        pid = driver.launch(
            args=[
                "--uitest-bridge",
                "--uitest-bridge-socket",
                str(bridge_socket),
            ],
            wait=False,
        )
        print(f"launched {args.bundle_id} pid={pid}", file=sys.stderr)

        _wait_for_bridge(bridge_client, timeout_s=args.bridge_timeout)
        print(f"bridge ready at {bridge_socket}", file=sys.stderr)

        bridge_client.send("workspace.open", {"path": str(research_root)})
        print(f"workspace opened: {research_root}", file=sys.stderr)

        runner = ScenarioRunner(research_root, driver=driver)
        result = runner.run(scenario)
        summary = result.to_summary()

        if args.json:
            print(json.dumps(summary, indent=2))
        else:
            print(_format_summary(summary))
        exit_code = 0 if result.succeeded else 2
    except DriverError as exc:
        print(f"driver error: {exc}", file=sys.stderr)
    except TimeoutError as exc:
        print(f"timeout: {exc}", file=sys.stderr)
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
    finally:
        if pid is not None and not args.keep_app_running:
            try:
                driver.terminate()
            except DriverError:
                pass
        try:
            driver.close()
        except Exception:
            pass
        if bridge_socket.exists():
            try:
                bridge_socket.unlink()
            except OSError:
                pass
        if tmp_root_owned and not args.keep_research_root:
            shutil.rmtree(research_root, ignore_errors=True)
        elif args.keep_research_root:
            print(f"keeping research root: {research_root}", file=sys.stderr)

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
